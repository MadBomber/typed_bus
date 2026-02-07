#!/usr/bin/env ruby
# frozen_string_literal: true

# 14 — Adaptive Rate Limiting (Throttle)
#
# Demonstrates asymptotic backoff using throttle: Float.
# The value is the remaining-capacity ratio at which backoff begins.
# Below that threshold, each publish sleeps for
# 1 / (max_pending * remaining_ratio) seconds — progressively slower
# as the channel fills, approaching a hard block at 0% remaining.
#
#   max_pending: 20, throttle: 0.5
#     50% remaining (10 slots) → delay = 1/(20*0.50) = 0.10s
#     25% remaining ( 5 slots) → delay = 1/(20*0.25) = 0.20s
#     10% remaining ( 2 slots) → delay = 1/(20*0.10) = 0.50s
#      5% remaining ( 1 slot)  → delay = 1/(20*0.05) = 1.00s
#      0% remaining            → hard block (existing behavior)
#
# Also shows bus-level defaults that apply to every channel.

require "logger"
require_relative "../lib/typed_bus"

logger = Logger.new($stdout)
logger.level = Logger::DEBUG
logger.formatter = proc do |severity, datetime, _progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  color = case severity
          when "WARN"  then "\e[33m"
          when "ERROR" then "\e[31m"
          when "DEBUG" then "\e[36m"
          when "INFO"  then "\e[32m"
          else "\e[0m"
          end
  "#{color}#{timestamp} [#{severity.ljust(5)}]\e[0m #{msg}\n"
end

TypedBus.logger = logger

# --- Example 1: Channel-level throttle ---

puts "=== Channel-level throttle (50% threshold) ==="
puts

channel = TypedBus::Channel.new(
  :pipeline,
  type: Integer,
  timeout: 5,
  max_pending: 20,
  throttle: 0.5
)

# Slow subscriber — takes 0.1s per message
channel.subscribe do |delivery|
  sleep 0.1
  delivery.ack!
end

Async do
  30.times do |i|
    puts "--- Publisher: sending message #{i + 1} ---"
    channel.publish(i + 1)
  end

  sleep 2
  puts
  puts "All messages processed."
  channel.close
end

puts
puts "=== Bus-level default throttle (50% threshold) ==="
puts

# --- Example 2: Bus-level defaults ---

bus = TypedBus::MessageBus.new(throttle: 0.5)

bus.add_channel(:orders, type: Integer, max_pending: 50, timeout: 5)      # inherits 0.5
bus.add_channel(:alerts, type: String, max_pending: 10, timeout: 5,
  throttle: 0.3)                                                           # overrides to 30%
bus.add_channel(:logs, type: String, max_pending: 100, timeout: 5,
  throttle: 0.0)                                                           # disables throttle

bus.subscribe(:orders) { |d| sleep 0.05; d.ack! }
bus.subscribe(:alerts) { |d| d.ack! }
bus.subscribe(:logs)   { |d| d.ack! }

Async do
  10.times { |i| bus.publish(:orders, i + 1) }
  3.times  { |i| bus.publish(:alerts, "alert-#{i}") }
  5.times  { |i| bus.publish(:logs, "log-#{i}") }

  sleep 1
  puts
  puts "Bus stats: #{bus.stats.to_h.inspect}"
  bus.close_all
end

# Clean up
TypedBus.logger = nil
