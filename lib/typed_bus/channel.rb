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
    # @param type [Class, nil] optional type constraint for messages
    # @param timeout [Numeric] seconds before delivery auto-nacks (default: 30)
    # @param max_pending [Integer, nil] backpressure limit (nil = unbounded)
    # @param stats [Stats, nil] optional stats tracker for counters
    # @param throttle [Float] capacity ratio (0.0..1.0) at which asymptotic backoff begins (0.0 = disabled)
    def initialize(name, type: nil, timeout: 30, max_pending: nil, stats: nil, throttle: 0.0)
      @name              = name
      @type              = type
      @timeout           = timeout
      @max_pending       = max_pending
      @stats             = stats
      @throttle          = throttle.to_f
      @subscribers       = {}
      @next_subscriber_id = 0
      @pending_deliveries = {}
      @active_deliveries  = []
      @closed            = false
      @dead_letter_queue = DeadLetterQueue.new
      @backpressure      = Async::Condition.new

      validate_throttle_config!

      log(:info, "channel created (type=#{type || 'any'}, timeout=#{timeout}s, max_pending=#{max_pending || 'unbounded'}, throttle=#{@throttle > 0 ? "#{(@throttle * 100).round}%" : 'off'})")
    end

    # Publish a message to all current subscribers.
    #
    # Blocks the calling fiber if the channel is bounded and at capacity.
    #
    # @param message [Object]
    # @raise [ArgumentError] if message doesn't match type constraint
    # @raise [RuntimeError] if channel is closed
    # @return [DeliveryTracker] the tracker for this message
    def publish(message)
      raise "Channel :#{@name} is closed" if @closed

      validate_type!(message)
      apply_throttle! if throttled?
      wait_for_capacity if bounded?

      subscriber_ids = @subscribers.keys

      if subscriber_ids.empty?
        log(:warn, "published with no subscribers, routing to DLQ (message=#{message.class})")
        dead_letter_no_subscribers(message)
        return nil
      end

      log(:info, "published message (type=#{message.class}, subscribers=#{subscriber_ids.size})")

      tracker = DeliveryTracker.new(message, channel_name: @name, subscriber_ids: subscriber_ids)
      @pending_deliveries[tracker.object_id] = tracker

      tracker.on_complete { record_stat(:delivered) }
      tracker.on_resolved { tracker_resolved(tracker) }

      subscriber_ids.each do |sub_id|
        handler = @subscribers[sub_id]
        next unless handler

        delivery = Delivery.new(
          message,
          channel_name: @name,
          subscriber_id: sub_id,
          timeout: @timeout,
          on_ack: ->(_id) {
            @active_deliveries.delete(delivery)
            tracker.ack(sub_id)
          },
          on_nack: ->(_id) {
            @active_deliveries.delete(delivery)
            tracker.nack(sub_id)
            @dead_letter_queue.push(delivery)
            record_stat(:dead_lettered)
            if delivery.timed_out?
              record_stat(:timed_out)
            else
              record_stat(:nacked)
            end
          }
        )

        @active_deliveries << delivery
        log(:debug, "notifying subscriber ##{sub_id} (message=#{message.class})")

        Async do
          handler.call(delivery)
        rescue StandardError => e
          log(:error, "subscriber ##{sub_id} raised #{e.class}: #{e.message}")
          delivery.nack! if delivery.pending?
        end
      end

      tracker
    end

    # Subscribe to messages on this channel.
    # The block receives a +Delivery+ object.
    #
    # @return [Integer] subscriber id (use for unsubscribe)
    def subscribe(&block)
      raise "Channel :#{@name} is closed" if @closed

      id = next_subscriber_id
      @subscribers[id] = block
      log(:info, "subscriber ##{id} registered (total=#{@subscribers.size})")
      id
    end

    # Remove a subscriber by id or block reference.
    #
    # @param id_or_block [Integer, Proc]
    def unsubscribe(id_or_block)
      case id_or_block
      when Integer
        @subscribers.delete(id_or_block)
        log(:info, "subscriber ##{id_or_block} unsubscribed (remaining=#{@subscribers.size})")
      else
        before = @subscribers.size
        @subscribers.delete_if { |_, v| v == id_or_block }
        log(:info, "subscriber unsubscribed by reference (removed=#{before - @subscribers.size}, remaining=#{@subscribers.size})")
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
    def close
      return if @closed

      @closed = true
      pending = @active_deliveries.count(&:pending?)
      log(:info, "closing (force-nacking #{pending} pending deliveries)")
      force_nack_pending
      @backpressure.signal
    end

    def closed?
      @closed
    end

    # Hard reset: cancel all timeout tasks, discard all pending state and DLQ.
    def clear!
      log(:info, "clearing all state (active=#{@active_deliveries.size}, pending=#{@pending_deliveries.size}, dlq=#{@dead_letter_queue.size})")
      @active_deliveries.each(&:cancel_timeout)
      @active_deliveries.clear
      @pending_deliveries.clear
      @dead_letter_queue.clear!
      @backpressure.signal
    end

    private

    def validate_throttle_config!
      return if @throttle == 0.0

      unless bounded?
        raise ArgumentError, "throttle requires max_pending on channel :#{@name}"
      end

      unless @throttle > 0.0 && @throttle < 1.0
        raise ArgumentError, "throttle must be between 0.0 and 1.0 (exclusive), got #{@throttle} on channel :#{@name}"
      end
    end

    def throttled?
      @throttle > 0.0 && bounded?
    end

    def apply_throttle!
      remaining_ratio = (@max_pending - @pending_deliveries.size).to_f / @max_pending
      return if remaining_ratio > @throttle

      effective_rate = @max_pending * remaining_ratio
      delay = 1.0 / effective_rate
      log(:debug, "throttle: #{(remaining_ratio * 100).round}% remaining, delay=#{delay.round(4)}s")
      record_stat(:throttled)
      sleep(delay)
    end

    def validate_type!(message)
      return unless @type
      return if message.is_a?(@type)

      log(:error, "type mismatch: expected #{@type}, got #{message.class}")
      raise ArgumentError, "Expected #{@type}, got #{message.class} on channel :#{@name}"
    end

    def bounded?
      !@max_pending.nil?
    end

    def wait_for_capacity
      log(:debug, "backpressure: waiting for capacity (pending=#{@pending_deliveries.size}, max=#{@max_pending})")
      while @pending_deliveries.size >= @max_pending && !@closed
        @backpressure.wait
      end
      log(:debug, "backpressure: capacity available (pending=#{@pending_deliveries.size})")
    end

    def tracker_resolved(tracker)
      @pending_deliveries.delete(tracker.object_id)
      @backpressure.signal if bounded?
    end

    def force_nack_pending
      @active_deliveries.dup.each do |delivery|
        delivery.nack! if delivery.pending?
      end
    end

    def dead_letter_no_subscribers(message)
      delivery = Delivery.new(message, channel_name: @name, subscriber_id: -1)
      delivery.nack!
      @dead_letter_queue.push(delivery)
      record_stat(:nacked)
      record_stat(:dead_lettered)
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
