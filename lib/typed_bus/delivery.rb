# frozen_string_literal: true

module TypedBus
  # Envelope wrapping a message delivered to a single subscriber.
  # Each subscriber receives its own Delivery instance for the same message.
  #
  # The subscriber must call +ack!+ or +nack!+ to resolve the delivery.
  # If neither is called before the timeout expires, the delivery auto-nacks.
  class Delivery
    attr_reader :message, :channel_name, :subscriber_id

    # @param message [Object] the published payload
    # @param channel_name [Symbol] originating channel
    # @param subscriber_id [Integer] identity of the target subscriber
    # @param timeout [Numeric] seconds before auto-nack (nil = no timeout)
    # @param on_ack [Proc, nil] called with subscriber_id on ack
    # @param on_nack [Proc, nil] called with subscriber_id on nack
    def initialize(message, channel_name:, subscriber_id:, timeout: nil, on_ack: nil, on_nack: nil)
      @message       = message
      @channel_name  = channel_name
      @subscriber_id = subscriber_id
      @on_ack        = on_ack
      @on_nack       = on_nack
      @state         = :pending
      @timed_out     = false
      @timeout_task  = nil

      start_timeout(timeout) if timeout
    end

    def ack!
      transition!(:acked)
      cancel_timeout
      log(:info, "acked")
      @on_ack&.call(@subscriber_id)
    end

    def nack!
      transition!(:nacked)
      cancel_timeout
      log(:warn, "nacked")
      @on_nack&.call(@subscriber_id)
    end

    def acked?    = @state == :acked
    def nacked?   = @state == :nacked
    def pending?  = @state == :pending
    def timed_out? = @timed_out

    # Cancel the timeout timer without resolving.
    def cancel_timeout
      @timeout_task&.stop
      @timeout_task = nil
    end

    private

    def transition!(new_state)
      raise "Delivery already resolved as #{@state}" unless pending?

      @state = new_state
    end

    def start_timeout(seconds)
      @timeout_task = Async do
        sleep(seconds)
        next unless pending?

        @timed_out = true
        transition!(:nacked)
        log(:warn, "timed out after #{seconds}s")
        @on_nack&.call(@subscriber_id)
      end
    end

    def log(level, message)
      TypedBus.logger&.send(level, "TypedBus::Delivery[:#{@channel_name}##{@subscriber_id}] #{message}")
    end
  end
end
