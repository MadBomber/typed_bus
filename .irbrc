# frozen_string_literal: true

require "bundler/setup"
require_relative "./lib/typed_bus"

TypedBus.logger = Logger.new('irb.log', level: :info)

def bus
  @bus ||= TypedBus::MessageBus.new
end
