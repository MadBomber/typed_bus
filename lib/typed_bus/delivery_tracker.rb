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
      @states       = subscriber_ids.each_with_object({}) { |id, h| h[id] = :pending }
      @on_complete    = nil
      @on_resolved    = nil
      @on_dead_letter = nil
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
      @states.values.all? { |s| s == :acked }
    end

    # True when all subscribers have resolved (acked or nacked).
    def fully_resolved?
      @states.values.none? { |s| s == :pending }
    end

    # Number of subscribers still pending.
    def pending_count
      @states.count { |_, s| s == :pending }
    end

    # Register a callback fired when all subscribers have resolved
    # and every one ACKed (successful delivery).
    def on_complete(&block)
      @on_complete = block
    end

    # Register a callback fired when all subscribers have resolved,
    # regardless of outcome (acked or nacked). Use for cleanup.
    def on_resolved(&block)
      @on_resolved = block
    end

    # Register a callback fired for each NACK, receiving the subscriber_id.
    def on_dead_letter(&block)
      @on_dead_letter = block
    end

    private

    def set_state(subscriber_id, state)
      unless @states.key?(subscriber_id)
        raise ArgumentError, "Unknown subscriber_id: #{subscriber_id}"
      end
      if @states[subscriber_id] != :pending
        raise "Subscriber #{subscriber_id} already resolved as #{@states[subscriber_id]}"
      end

      @states[subscriber_id] = state
    end

    def check_resolution
      return unless fully_resolved? && !@resolved

      @resolved = true

      if fully_delivered?
        log(:info, "fully delivered (all #{@states.size} subscribers acked)")
        @on_complete&.call
      else
        nacked = @states.count { |_, s| s == :nacked }
        log(:warn, "resolved with #{nacked} nack(s) out of #{@states.size} subscribers")
      end

      @on_resolved&.call
    end

    def fire_dead_letter(subscriber_id)
      @on_dead_letter&.call(subscriber_id)
    end

    def log(level, message)
      TypedBus.logger&.send(level, "TypedBus::DeliveryTracker[:#{@channel_name}] #{message}")
    end
  end
end
