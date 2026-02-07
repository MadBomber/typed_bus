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
    attr_reader :stats, :config

    # @param timeout [Numeric, Symbol] delivery ACK deadline (overrides global default)
    # @param max_pending [Integer, nil, Symbol] backpressure limit (overrides global default)
    # @param throttle [Float, Symbol] default throttle threshold for all channels (overrides global default)
    def initialize(timeout: :use_default, max_pending: :use_default, throttle: :use_default)
      global  = TypedBus.configuration
      @config = global.dup
      resolved = global.resolve(timeout: timeout, max_pending: max_pending, throttle: throttle)
      @config.timeout     = resolved[:timeout]
      @config.max_pending = resolved[:max_pending]
      @config.throttle    = resolved[:throttle]

      @channels = {}
      @stats = Stats.new
      effective_throttle = @config.throttle.to_f
      log(:info, "message bus initialized (default_throttle=#{effective_throttle > 0 ? "#{(effective_throttle * 100).round}%" : 'off'})")
    end

    # Register a named channel.
    #
    # When a parameter is not provided (left as +:use_default+), the bus-level
    # config value is used. Pass an explicit value to override for this channel.
    #
    # @param name [Symbol]
    # @param type [Class, nil] optional type constraint
    # @param timeout [Numeric, Symbol] delivery ACK deadline in seconds
    # @param max_pending [Integer, nil, Symbol] backpressure limit
    # @param throttle [Float, Symbol] capacity ratio where backoff begins (0.0 = disabled)
    # @return [Channel]
    def add_channel(name, type: nil, timeout: :use_default, max_pending: :use_default, throttle: :use_default)
      resolved = @config.resolve(timeout: timeout, max_pending: max_pending, throttle: throttle)
      effective_timeout     = resolved[:timeout]
      effective_max_pending = resolved[:max_pending]
      effective_throttle    = resolved[:throttle]

      log(:info, "adding channel :#{name} (type=#{type || 'any'}, timeout=#{effective_timeout}s, max_pending=#{effective_max_pending || 'unbounded'})")
      channel = Channel.new(name, type: type, timeout: effective_timeout, max_pending: effective_max_pending, stats: @stats, throttle: effective_throttle)
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
