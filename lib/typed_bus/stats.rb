# frozen_string_literal: true

module TypedBus
  # Simple counter map for message bus activity.
  # Fiber-safe — no mutex needed within a single Async reactor.
  class Stats
    attr_reader :data

    def initialize
      @data = {}
    end

    # Increment a named counter.
    # @param key [Symbol]
    # @return [Integer] new value
    def increment(key)
      @data[key] = (@data[key] || 0) + 1
    end

    # Read a counter value.
    # @param key [Symbol]
    # @return [Integer]
    def [](key)
      @data[key] || 0
    end

    # Reset all counters to zero.
    def reset!
      @data.transform_values! { 0 }
    end

    # Return a snapshot of all counters.
    # @return [Hash<Symbol, Integer>]
    def to_h
      @data.dup
    end
  end
end
