#!/usr/bin/env ruby
# frozen_string_literal: true

# 11 — Basic Logging
#
# Shows how to enable logging by assigning a standard Ruby Logger to
# TypedBus.logger. Every lifecycle event is logged: channel creation,
# subscriber registration, message publish, delivery notification, ack/nack,
# and tracker resolution.

require "logger"
require_relative "../lib/typed_bus"

# Configure a colorized logger writing to STDOUT
logger = Logger.new($stdout)
logger.formatter = proc do |severity, datetime, _progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  "#{timestamp} [#{severity.ljust(5)}] #{msg}\n"
end

# Assigning a logger applies the configured log_level (INFO by default),
# so set DEBUG through the configuration rather than on the logger itself.
TypedBus.configure do |config|
  config.logger    = logger
  config.log_level = Logger::DEBUG
end

# --- Set up a bus with two channels ---

bus = TypedBus::MessageBus.new
bus.add_channel(:orders, type: String, timeout: 2)
bus.add_channel(:alerts, timeout: 2)

# --- Register subscribers ---

bus.subscribe(:orders) do |delivery|
  sleep 0.05 # simulate work
  delivery.ack!
end

bus.subscribe(:orders) do |delivery|
  sleep 0.1
  delivery.ack!
end

bus.subscribe(:alerts) do |delivery|
  delivery.ack!
end

# --- Publish messages ---

Async do
  bus.publish(:orders, "Order #1001")
  bus.publish(:orders, "Order #1002")
  bus.publish(:alerts, "System healthy")
  sleep 0.3 # let deliveries settle
end

puts
puts "--- Stats ---"
bus.stats.to_h.each { |k, v| puts "  #{k}: #{v}" }

# Clean up
TypedBus.logger = nil
