# frozen_string_literal: true

module TypedBus
  # Registry facade for named, typed pub/sub channels.
  #
  # @example
  #   bus = TypedBus::MessageBus.new
  #   bus.add_channel(:events, type: MyEvent)
  #
  #   bus.subscribe(:events) do |delivery|
  #     puts delivery.message
  #     delivery.ack!
  #   end
  #
  #   Async { bus.publish(:events, MyEvent.new(...)) }
  #
  class MessageBus
    attr_reader :stats

    # @param throttle [Float] default throttle threshold for all channels (0.0 = disabled)
    def initialize(throttle: 0.0)
      @channels = {}
      @stats = Stats.new
      @default_throttle = throttle.to_f
      log(:info, "message bus initialized (default_throttle=#{@default_throttle > 0 ? "#{(@default_throttle * 100).round}%" : 'off'})")
    end

    # Register a named channel.
    #
    # When +throttle+ is not provided, the bus-level default is used.
    # Pass an explicit +throttle: 0.0+ to suppress the default for a
    # specific channel, or a value like +0.5+ to set the backoff threshold.
    #
    # @param name [Symbol]
    # @param type [Class, nil] optional type constraint
    # @param timeout [Numeric] delivery ACK deadline in seconds
    # @param max_pending [Integer, nil] backpressure limit
    # @param throttle [Float, Symbol] capacity ratio where backoff begins (0.0 = disabled)
    # @return [Channel]
    def add_channel(name, type: nil, timeout: 30, max_pending: nil, throttle: :use_default)
      effective_throttle = resolve_throttle(throttle)
      log(:info, "adding channel :#{name} (type=#{type || 'any'}, timeout=#{timeout}s, max_pending=#{max_pending || 'unbounded'})")
      channel = Channel.new(name, type: type, timeout: timeout, max_pending: max_pending, stats: @stats, throttle: effective_throttle)
      @channels[name] = channel
      channel
    end

    # Close and remove a channel.
    # @param name [Symbol]
    def remove_channel(name)
      log(:info, "removing channel :#{name}")
      channel = @channels.delete(name)
      channel&.close
    end

    # Publish a message to a named channel.
    # @param channel_name [Symbol]
    # @param message [Object]
    def publish(channel_name, message)
      channel = fetch_channel!(channel_name)
      @stats.increment(:"#{channel_name}_published")
      channel.publish(message)
    end

    # Subscribe to a named channel.
    # The block receives a +Delivery+ object.
    # @param channel_name [Symbol]
    # @return [Integer] subscriber id
    def subscribe(channel_name, &block)
      channel = fetch_channel!(channel_name)
      channel.subscribe(&block)
    end

    # Unsubscribe from a named channel.
    # @param channel_name [Symbol]
    # @param id_or_block [Integer, Proc]
    def unsubscribe(channel_name, id_or_block)
      channel = fetch_channel!(channel_name)
      channel.unsubscribe(id_or_block)
    end

    # Check if a channel has pending (unresolved) deliveries.
    # @param channel_name [Symbol]
    # @return [Boolean]
    def pending?(channel_name)
      channel = fetch_channel!(channel_name)
      channel.pending?
    end

    # Number of unresolved deliveries on a channel.
    # @param channel_name [Symbol]
    # @return [Integer]
    def pending_count(channel_name)
      channel = fetch_channel!(channel_name)
      channel.pending_count
    end

    # Access a channel's dead letter queue.
    # @param channel_name [Symbol]
    # @return [DeadLetterQueue]
    def dead_letters(channel_name)
      channel = fetch_channel!(channel_name)
      channel.dead_letter_queue
    end

    # Close a specific channel.
    # @param channel_name [Symbol]
    def close(channel_name)
      channel = fetch_channel!(channel_name)
      channel.close
    end

    # Close all channels (graceful shutdown).
    def close_all
      log(:info, "closing all channels (#{@channels.size} channels)")
      @channels.each_value(&:close)
    end

    # List registered channel names.
    # @return [Array<Symbol>]
    def channel_names
      @channels.keys
    end

    # Check if a channel exists.
    # @param name [Symbol]
    # @return [Boolean]
    def channel?(name)
      @channels.key?(name)
    end

    # Close all channels, clear DLQs, and reset stats.
    def clear!
      log(:info, "clearing all channels and resetting stats")
      @channels.each_value(&:clear!)
      @stats.reset!
    end

    private

    def resolve_throttle(value)
      value == :use_default ? @default_throttle : value
    end

    def fetch_channel!(name)
      channel = @channels[name]
      raise ArgumentError, "Unknown channel: #{name}" unless channel

      channel
    end

    def log(level, message)
      TypedBus.logger&.send(level, "TypedBus::MessageBus #{message}")
    end
  end
end
