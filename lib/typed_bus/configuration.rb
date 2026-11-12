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

    attr_accessor :timeout, :throttle
    attr_reader :max_pending, :logger, :log_level

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
