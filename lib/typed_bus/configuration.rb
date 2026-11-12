# frozen_string_literal: true

module TypedBus
  # Holds configurable defaults for the message bus system.
  #
  # Three-tier cascade: Global → Bus → Channel.
  # Each tier can override the one above using explicit values.
  # The sentinel +:use_default+ means "inherit from the tier above."
  #
  # @example Global defaults
  #   TypedBus.configure do |config|
  #     config.timeout     = 60
  #     config.max_pending = 500
  #     config.throttle    = 0.5
  #     config.logger      = Logger.new($stdout)
  #     config.log_level   = Logger::DEBUG
  #   end
  class Configuration
    DEFAULTS = {
      timeout: 30,
      max_pending: nil,
      throttle: 0.0,
      logger: nil,
      log_level: Logger::INFO
    }.freeze

    # @return [Numeric, nil] delivery ACK deadline in seconds; nil = never auto-nack
    attr_accessor :timeout
    attr_reader :max_pending, :throttle, :logger, :log_level

    # Ensure a backpressure limit is usable: +nil+ (unbounded) or a
    # positive Integer. Zero and negative limits can never accept a publish.
    #
    # @param value [Object] candidate max_pending
    # @raise [ArgumentError] if value is neither nil nor a positive Integer
    # @return [Integer, nil] the validated value
    def self.validate_max_pending!(value)
      return value if value.nil? || (value.is_a?(Integer) && value.positive?)

      raise ArgumentError, "max_pending must be nil or a positive Integer, got #{value.inspect}"
    end

    # Ensure a throttle threshold is usable: +nil+ or +0+ (off), or a real
    # number strictly between 0 and 1. Whether the channel is bounded is
    # checked when the channel is created.
    #
    # @param value [Object] candidate throttle
    # @param context [String, nil] text appended to the error message
    # @raise [ArgumentError] if value is not nil, 0, or a number in (0, 1)
    # @return [Numeric, nil] the validated value
    def self.validate_throttle!(value, context = nil)
      return value if value.nil?
      return value if value.is_a?(Numeric) && value.real? && (value.zero? || (value > 0 && value < 1))

      raise ArgumentError, "throttle must be 0 (off) or between 0.0 and 1.0 (exclusive), got #{value.inspect}#{context}"
    end

    def initialize
      @timeout     = DEFAULTS[:timeout]
      @max_pending = DEFAULTS[:max_pending]
      @throttle    = DEFAULTS[:throttle]
      @logger      = DEFAULTS[:logger]
      @log_level   = DEFAULTS[:log_level]
    end

    # Set the backpressure limit.
    # @param value [Integer, nil] a positive Integer, or nil for unbounded
    # @raise [ArgumentError] if value is neither nil nor a positive Integer
    def max_pending=(value)
      @max_pending = self.class.validate_max_pending!(value)
    end

    # Set the throttle threshold.
    # @param value [Numeric, nil] 0 or nil for off, or a number strictly between 0 and 1
    # @raise [ArgumentError] if value is not nil, 0, or a number in (0, 1)
    def throttle=(value)
      @throttle = self.class.validate_throttle!(value)
    end

    # Set the logger and apply the current log_level to it.
    # @param log [Logger, nil]
    def logger=(log)
      @logger = log
      @logger&.level = @log_level
    end

    # Set the log level and apply it to the current logger.
    # @param level [Integer] a Logger constant (Logger::DEBUG, Logger::INFO, etc.)
    def log_level=(level)
      @log_level = level
      @logger&.level = level
    end

    # Merge overrides on top of this configuration's values.
    # Parameters set to +:use_default+ inherit from this config.
    #
    # @param timeout [Numeric, Symbol] delivery ACK deadline
    # @param max_pending [Integer, nil, Symbol] backpressure limit
    # @param throttle [Float, Symbol] capacity ratio for adaptive backoff
    # @return [Hash] resolved values
    def resolve(timeout: :use_default, max_pending: :use_default, throttle: :use_default)
      {
        timeout:     timeout     == :use_default ? @timeout     : timeout,
        max_pending: max_pending == :use_default ? @max_pending : max_pending,
        throttle:    throttle    == :use_default ? @throttle    : throttle
      }
    end
  end
end
