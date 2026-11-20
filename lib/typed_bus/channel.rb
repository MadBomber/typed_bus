# frozen_string_literal: true

module TypedBus
  # A named, typed pub/sub channel with explicit acknowledgment tracking.
  #
  # Subscribers receive +Delivery+ objects and must call +ack!+ or +nack!+.
  # Messages are considered delivered only when ALL subscribers ACK.
  # NACKed or timed-out deliveries go to the dead letter queue.
  #
  # Optionally bounded: when +max_pending+ is set, publishers block until
  # pending deliveries drain below the limit.
  class Channel
    attr_reader :name, :type, :dead_letter_queue

    # @param name [Symbol] channel name
    # @param type [Class, Module, nil] optional type constraint for messages
    # @param timeout [Numeric, nil] seconds before delivery auto-nacks (default: 30); nil = never auto-nack
    # @param max_pending [Integer, nil] backpressure limit; a positive Integer or nil (unbounded)
    # @param stats [Stats, nil] optional stats tracker for counters
    # @param throttle [Numeric, nil] remaining-capacity ratio at which asymptotic backoff begins;
    #   0 or nil = off, else strictly between 0 and 1
    # @raise [ArgumentError] if type, max_pending, or throttle is invalid
    def initialize(name, type: nil, timeout: 30, max_pending: nil, stats: nil, throttle: 0.0)
      @name              = name
      @type              = type
      @timeout           = timeout
      @max_pending       = max_pending
      @stats             = stats
      @throttle          = Configuration.validate_throttle!(throttle, " on channel :#{name}").to_f
      @subscribers       = {}
      @next_subscriber_id = 0
      @pending_deliveries = {}.compare_by_identity
      @active_deliveries  = []
      @closed            = false
      @dead_letter_queue = DeadLetterQueue.new
      @backpressure      = Async::Condition.new

      validate_type_config!
      Configuration.validate_max_pending!(@max_pending)
      validate_throttle_config!

      log(:info,
          "channel created (type=#{type || 'any'}, timeout=#{timeout ? "#{timeout}s" : 'none'}, " \
          "max_pending=#{max_pending || 'unbounded'}, " \
          "throttle=#{@throttle.positive? ? "#{(@throttle * 100).round}%" : 'off'})")
    end

    # Publish a message to all current subscribers.
    #
    # Blocks the calling fiber if the channel is bounded and at capacity.
    #
    # @param message [Object]
    # @raise [ArgumentError] if message doesn't match type constraint
    # @raise [RuntimeError] if channel is closed, including while the
    #   publisher was waiting on throttle or backpressure
    # @return [DeliveryTracker, nil] the tracker, or nil when there are no
    #   subscribers and the message was dead-lettered
    def publish(message)
      admit!(message)

      # Snapshot ids and handlers together so every id the tracker waits on
      # gets a Delivery, even if a handler unsubscribes someone mid-publish.
      subscribers = @subscribers.to_a
      return dead_letter_no_subscribers(message) if subscribers.empty?

      log(:info, "published message (type=#{message.class}, subscribers=#{subscribers.size})")

      tracker = track(message, subscribers.map(&:first))
      subscribers.each { |sub_id, handler| deliver(tracker, sub_id, handler) }
      tracker
    end

    # Subscribe to messages on this channel.
    # The block receives a +Delivery+ object.
    #
    # @raise [ArgumentError] if no block is given
    # @raise [RuntimeError] if channel is closed
    # @return [Integer] subscriber id (use for unsubscribe)
    def subscribe(&block)
      raise ArgumentError, "Channel :#{@name} subscribe requires a block" unless block
      ensure_open!

      id = next_subscriber_id
      @subscribers[id] = block
      log(:info, "subscriber ##{id} registered (total=#{@subscribers.size})")
      id
    end

    # Remove a subscriber by id or block reference.
    #
    # @param id_or_block [Integer, Proc]
    def unsubscribe(id_or_block)
      if id_or_block.is_a?(Integer)
        unsubscribe_id(id_or_block)
      else
        unsubscribe_handler(id_or_block)
      end
    end

    # Number of active subscribers.
    def subscriber_count
      @subscribers.size
    end

    # Number of unresolved delivery trackers.
    def pending_count
      @pending_deliveries.size
    end

    # True when there are unresolved deliveries.
    def pending?
      !@pending_deliveries.empty?
    end

    # Close the channel. Stops accepting new publishes/subscribes.
    # Pending deliveries are force-nacked (routed to DLQ with stats).
    # Publishers waiting for capacity are always woken and raise the
    # closed error, even if an on_dead_letter callback raises here.
    # Every pending delivery is nacked even if an on_dead_letter callback
    # raises; the first such error is re-raised once all are handled.
    def close
      return if @closed

      @closed = true
      pending = @active_deliveries.count(&:pending?)
      log(:info, "closing (force-nacking #{pending} pending deliveries)")
      force_nack_pending
    ensure
      @backpressure.signal
    end

    def closed?
      @closed
    end

    # Hard reset: cancel all timeout tasks, discard all pending state and DLQ.
    def clear!
      log(:info,
          "clearing all state (active=#{@active_deliveries.size}, pending=#{@pending_deliveries.size}, dlq=#{@dead_letter_queue.size})")
      @active_deliveries.each(&:cancel_timeout)
      @active_deliveries.clear
      @pending_deliveries.clear
      @dead_letter_queue.clear!
      @backpressure.signal
    end

    private

    def ensure_open!
      raise "Channel :#{@name} is closed" if @closed
    end

    # Everything that can reject or delay a publish before fan-out.
    def admit!(message)
      ensure_open!
      validate_type!(message)
      apply_throttle! if throttled?
      wait_for_capacity if bounded?
      ensure_open! # the channel may have closed while we waited
    end

    def unsubscribe_id(id)
      @subscribers.delete(id)
      log(:info, "subscriber ##{id} unsubscribed (remaining=#{@subscribers.size})")
    end

    def unsubscribe_handler(handler)
      ids = @subscribers.select { |_, registered| registered == handler }.keys
      ids.each { |id| @subscribers.delete(id) }
      log(:info, "subscriber unsubscribed by reference (removed=#{ids.size}, remaining=#{@subscribers.size})")
    end

    def validate_type_config!
      return if @type.nil? || @type.is_a?(Module)

      raise ArgumentError, "type must be a Class or Module, got #{@type.inspect} on channel :#{@name}"
    end

    # The range is checked by Configuration.validate_throttle! in #initialize.
    def validate_throttle_config!
      return if @throttle == 0.0 || bounded?

      raise ArgumentError, "throttle requires max_pending on channel :#{@name}"
    end

    def throttled?
      @throttle > 0.0 && bounded?
    end

    def apply_throttle!
      remaining_ratio = (@max_pending - @pending_deliveries.size).to_f / @max_pending
      return if remaining_ratio > @throttle
      # At or over capacity the delay would be infinite; let backpressure
      # (wait_for_capacity) do the blocking instead of sleeping forever.
      return if remaining_ratio <= 0.0

      effective_rate = @max_pending * remaining_ratio
      delay = 1.0 / effective_rate
      log(:debug, "throttle: #{(remaining_ratio * 100).round}% remaining, delay=#{delay.round(4)}s")
      record_stat(:throttled)
      sleep(delay)
    end

    def validate_type!(message)
      return unless @type
      return if message.is_a?(@type)

      actual = message.class
      log(:error, "type mismatch: expected #{@type}, got #{actual}")
      raise ArgumentError, "Expected #{@type}, got #{actual} on channel :#{@name}"
    end

    def bounded?
      !@max_pending.nil?
    end

    def wait_for_capacity
      pending = pending_count
      return if pending < @max_pending

      log(:debug, "backpressure: waiting for capacity (pending=#{pending}, max=#{@max_pending})")
      log(:debug, "backpressure: capacity available (pending=#{wait_while_full})")
    end

    # Block until a tracker resolves below the limit or the channel closes.
    # @return [Integer] the pending count once the wait is over
    def wait_while_full
      @backpressure.wait while full? && !closed?
      pending_count
    end

    def full?
      pending_count >= @max_pending
    end

    def tracker_resolved(tracker)
      @pending_deliveries.delete(tracker)
      @backpressure.signal if bounded?
    end

    # Nack every pending delivery. An error from one (such as a raising
    # on_dead_letter callback) must not leave the rest pending, so the
    # first error is kept and re-raised after the loop.
    def force_nack_pending
      first_error = nil
      @active_deliveries.dup.each do |delivery|
        delivery.nack! if delivery.pending?
      rescue StandardError => error
        first_error ||= error
      end
      raise first_error if first_error
    end

    # Start tracking one publish across its subscribers.
    # @return [DeliveryTracker]
    def track(message, subscriber_ids)
      tracker = DeliveryTracker.new(message, channel_name: @name, subscriber_ids: subscriber_ids)
      @pending_deliveries[tracker] = tracker

      tracker.on_complete { record_stat(:delivered) }
      tracker.on_resolved { tracker_resolved(tracker) }
      tracker
    end

    # Hand one subscriber its Delivery for the tracked message.
    def deliver(tracker, sub_id, handler)
      delivery = build_delivery(tracker, sub_id)
      @active_deliveries << delivery

      # An earlier handler may have closed the channel mid-fan-out. close
      # only force-nacks deliveries that already exist, so dead-letter
      # this one the same way instead of dispatching it.
      return delivery.nack! if closed?

      log(:debug, "notifying subscriber ##{sub_id} (message=#{tracker.message.class})")
      dispatch(handler, delivery)
    end

    # Build the Delivery envelope for one subscriber, wired to the tracker.
    # @return [Delivery]
    def build_delivery(tracker, sub_id)
      delivery = Delivery.new(
        tracker.message,
        channel_name: @name,
        subscriber_id: sub_id,
        timeout: @timeout,
        on_ack: ->(_id) { delivery_acked(delivery, tracker) },
        on_nack: ->(_id) { delivery_nacked(delivery, tracker) }
      )
    end

    # Run the subscriber's handler in its own task; a raising handler nacks.
    def dispatch(handler, delivery)
      Async do
        handler.call(delivery)
      rescue StandardError => error
        log(:error, "subscriber ##{delivery.subscriber_id} raised #{error.class}: #{error.message}")
        delivery.nack! if delivery.pending?
      end
    end

    def delivery_acked(delivery, tracker)
      @active_deliveries.delete(delivery)
      tracker.ack(delivery.subscriber_id)
    end

    def delivery_nacked(delivery, tracker)
      @active_deliveries.delete(delivery)
      tracker.nack(delivery.subscriber_id)
      # Count before pushing: the DLQ runs a user callback that may raise.
      record_stat(:dead_lettered)
      record_stat(delivery.timed_out? ? :timed_out : :nacked)
      @dead_letter_queue.push(delivery)
    end

    # A publish with nobody listening goes straight to the DLQ.
    # @return [nil]
    def dead_letter_no_subscribers(message)
      log(:warn, "published with no subscribers, routing to DLQ (message=#{message.class})")
      delivery = Delivery.new(message, channel_name: @name, subscriber_id: -1)
      delivery.nack!
      record_stat(:nacked)
      record_stat(:dead_lettered)
      @dead_letter_queue.push(delivery)
      nil
    end

    def record_stat(suffix)
      @stats&.increment(:"#{@name}_#{suffix}")
    end

    def next_subscriber_id
      @next_subscriber_id += 1
    end

    def log(level, message)
      TypedBus.logger&.send(level, "TypedBus::Channel[:#{@name}] #{message}")
    end
  end
end
