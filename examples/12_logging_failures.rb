#!/usr/bin/env ruby
# frozen_string_literal: true

# 12 — Logging Failures: NACKs, Timeouts, and Dead Letter Queue
#
# Demonstrates log output for failure scenarios:
# - Explicit nack! by a subscriber
# - Delivery timeout (subscriber never responds)
# - Publishing with no subscribers (auto dead-letter)
# - Dead letter queue drain

require "logger"
require_relative "../lib/typed_bus"

logger = Logger.new($stdout)
logger.level = Logger::DEBUG
logger.formatter = proc do |severity, datetime, _progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  color = case severity
          when "WARN"  then "\e[33m" # yellow
          when "ERROR" then "\e[31m" # red
          when "DEBUG" then "\e[36m" # cyan
          else "\e[0m"
          end
  "#{color}#{timestamp} [#{severity.ljust(5)}]\e[0m #{msg}\n"
end

TypedBus.logger = logger

bus = TypedBus::MessageBus.new

# Short timeout so the demo runs quickly
bus.add_channel(:jobs, type: String, timeout: 0.3)

# Subscriber that always rejects
bus.subscribe(:jobs) do |delivery|
  delivery.nack!
end

# Subscriber that never responds (will timeout)
bus.subscribe(:jobs) do |_delivery|
  # intentionally doing nothing — delivery will time out
end

Async do
  puts "=== Publishing to channel with nack + timeout subscribers ==="
  bus.publish(:jobs, "Job A")
  sleep 0.5 # wait for timeout

  puts
  puts "=== Publishing to channel with no subscribers ==="
  bus.remove_channel(:jobs)
  bus.add_channel(:empty_channel, timeout: 0.3)
  bus.publish(:empty_channel, "Lost message")

  puts
  puts "=== Draining dead letter queue ==="
  dlq = bus.dead_letters(:empty_channel)
  dlq.drain do |dead|
    puts "  Drained: channel=:#{dead.channel_name} message=#{dead.message.inspect}"
  end
end

# Clean up
TypedBus.logger = nil
