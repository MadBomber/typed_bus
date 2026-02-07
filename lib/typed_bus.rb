# frozen_string_literal: true

require "async"
require "async/condition"
require "logger"

require_relative "typed_bus/version"
require_relative "typed_bus/stats"
require_relative "typed_bus/delivery"
require_relative "typed_bus/delivery_tracker"
require_relative "typed_bus/dead_letter_queue"
require_relative "typed_bus/channel"
require_relative "typed_bus/message_bus"

module TypedBus
  class << self
    # Assign a standard Ruby Logger to enable logging.
    # When nil (the default), no log output is produced.
    #
    # @example
    #   TypedBus.logger = Logger.new($stdout)
    attr_accessor :logger
  end
end
