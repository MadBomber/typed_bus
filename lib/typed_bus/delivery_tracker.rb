# frozen_string_literal: true

module TypedBus
  # Tracks the delivery state of a single published message across N subscribers.
  #
  # Created per +publish+ call. Each subscriber gets a Delivery envelope;
  # the tracker aggregates their ack/nack responses and fires callbacks
  # when the message is fully delivered or needs dead-lettering.
  class DeliveryTracker
    attr_reader :message, :channel_name

    # @param message [Object] the published payload
    # @param channel_name [Symbol]
    # @param subscriber_ids [Array<Integer>] set of subscribers for this message
    def initialize(message, channel_name:, subscriber_ids:)
      @message      = message
      @channel_name = channel_name
      @states       = subscriber_ids.to_h { |id| [id, :pending] }
      @on_complete    = []
      @on_resolved    = []
      @on_dead_letter = []
      @resolved       = false
    end

    # Record an ACK from a subscriber.
    def ack(subscriber_id)
      set_state(subscriber_id, :acked)
      check_resolution
    end

    # Record a NACK from a subscriber.
    def nack(subscriber_id)
      set_state(subscriber_id, :nacked)
      fire_dead_letter(subscriber_id)
      check_resolution
    end

    # True when every subscriber has ACKed.
    def fully_delivered?
      @states.values.all? { |state| state == :acked }
    end

    # True when all subscribers have resolved (acked or nacked).
    def fully_resolved?
      @states.values.none? { |state| state == :pending }
    end

    # Number of subscribers still pending.
    def pending_count
      @states.count { |_, state| state == :pending }
    end

    # Register a callback fired when all subscribers have resolved
    # and every one ACKed (successful delivery).
    # Callbacks accumulate and run in registration order.
    def on_complete(&block)
      register(@on_complete, block)
    end

    # Register a callback fired when all subscribers have resolved,
    # regardless of outcome (acked or nacked). Use for cleanup.
    # Callbacks accumulate and run in registration order.
    def on_resolved(&block)
      register(@on_resolved, block)
    end

    # Register a callback fired for each NACK, receiving the subscriber_id.
    # Callbacks accumulate and run in registration order.
    def on_dead_letter(&block)
      register(@on_dead_letter, block)
    end

    private

    # Append a callback; a call without a block registers nothing.
    def register(callbacks, block)
      callbacks << block if block
    end

    def set_state(subscriber_id, state)
      unless @states.key?(subscriber_id)
        raise ArgumentError, "Unknown subscriber_id: #{subscriber_id}"
      end

      current = @states[subscriber_id]
      raise "Subscriber #{subscriber_id} already resolved as #{current}" if current != :pending

      @states[subscriber_id] = state
    end

    def check_resolution
      return unless fully_resolved? && !@resolved

      @resolved = true
      total = @states.size

      if fully_delivered?
        log(:info, "fully delivered (all #{total} subscribers acked)")
        @on_complete.each(&:call)
      else
        nacked = @states.count { |_, state| state == :nacked }
        log(:warn, "resolved with #{nacked} nack(s) out of #{total} subscribers")
      end

      @on_resolved.each(&:call)
    end

    def fire_dead_letter(subscriber_id)
      @on_dead_letter.each { |callback| callback.call(subscriber_id) }
    end

    def log(level, message)
      TypedBus.logger&.send(level, "TypedBus::DeliveryTracker[:#{@channel_name}] #{message}")
    end
  end
end
