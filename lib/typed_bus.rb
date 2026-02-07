# frozen_string_literal: true

require "async"
require "async/condition"
require "logger"

require_relative "typed_bus/version"
require_relative "typed_bus/configuration"
require_relative "typed_bus/stats"
require_relative "typed_bus/delivery"
require_relative "typed_bus/delivery_tracker"
require_relative "typed_bus/dead_letter_queue"
require_relative "typed_bus/channel"
require_relative "typed_bus/message_bus"

module TypedBus
  class << self
    # The global Configuration instance.
    # @return [Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Replace the global Configuration.
    # @param config [Configuration]
    def configuration=(config)
      @configuration = config
    end

    # Yield the global Configuration for block-style setup.
    #
    # @example
    #   TypedBus.configure do |config|
    #     config.timeout = 60
    #     config.logger  = Logger.new($stdout)
    #   end
    def configure
      yield configuration
    end

    # Restore factory defaults (useful in tests).
    def reset_configuration!
      @configuration = Configuration.new
    end

    # Shortcut — read the global logger.
    # @return [Logger, nil]
    def logger
      configuration.logger
    end

    # Shortcut — set the global logger.
    # @param log [Logger, nil]
    def logger=(log)
      configuration.logger = log
    end
  end
end

TB = TypedBus
