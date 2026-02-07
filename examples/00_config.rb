#!/usr/bin/env ruby
# frozen_string_literal: true

# 00 — Three-Tier Configuration Cascade
#
# TypedBus resolves configurable parameters through three tiers:
#
#   Global  →  Bus  →  Channel
#
# Each tier inherits from the one above unless explicitly overridden.
# Omitting a parameter (or passing :use_default) inherits from the parent.
# Passing an explicit value — including nil — overrides the parent.
#
# Configurable parameters and their factory defaults:
#
#   timeout      30           Delivery ACK deadline in seconds
#   max_pending  nil          Backpressure limit (nil = unbounded)
#   throttle     0.0          Capacity ratio for adaptive backoff (0.0 = disabled)
#   logger       nil          Ruby Logger instance (global-only)
#   log_level    Logger::INFO Log level applied to the logger (global-only)

require "logger"
require_relative "../lib/typed_bus"

# ─── Tier 1: Global Configuration ────────────────────────────────────

puts "=== Tier 1: Global Configuration ==="
puts

TypedBus.configure do |config|
  config.timeout     = 60
  config.max_pending = 500
  config.throttle    = 0.5
  config.logger      = Logger.new($stdout)
  config.log_level   = Logger::WARN
end

puts "Global timeout:     #{TypedBus.configuration.timeout}"
puts "Global max_pending: #{TypedBus.configuration.max_pending}"
puts "Global throttle:    #{TypedBus.configuration.throttle}"
puts "Global logger:      #{TypedBus.logger.class}"
puts "Global log_level:   #{TypedBus.configuration.log_level} (#{%w[DEBUG INFO WARN ERROR FATAL][TypedBus.configuration.log_level]})"
puts

# Logger shortcuts work too:
#   TypedBus.logger = Logger.new($stdout)
#   TypedBus.logger  # => the Logger instance
#
# Setting log_level automatically applies it to the logger:
#   config.log_level = Logger::DEBUG  # logger.level is now DEBUG

# ─── Tier 2: Bus-Level Overrides ─────────────────────────────────────

puts "=== Tier 2: Bus-Level Overrides ==="
puts

# Bus A: inherits everything from global
bus_a = TypedBus::MessageBus.new
puts "Bus A (all inherited):"
puts "  timeout:     #{bus_a.config.timeout}"       # => 60
puts "  max_pending: #{bus_a.config.max_pending}"   # => 500
puts "  throttle:    #{bus_a.config.throttle}"       # => 0.5
puts

# Bus B: overrides timeout, inherits the rest
bus_b = TypedBus::MessageBus.new(timeout: 10)
puts "Bus B (timeout overridden):"
puts "  timeout:     #{bus_b.config.timeout}"       # => 10
puts "  max_pending: #{bus_b.config.max_pending}"   # => 500
puts "  throttle:    #{bus_b.config.throttle}"       # => 0.5
puts

# Bus C: overrides all three
bus_c = TypedBus::MessageBus.new(timeout: 5, max_pending: nil, throttle: 0.0)
puts "Bus C (all overridden):"
puts "  timeout:     #{bus_c.config.timeout}"       # => 5
puts "  max_pending: #{bus_c.config.max_pending.inspect}"  # => nil (unbounded)
puts "  throttle:    #{bus_c.config.throttle}"       # => 0.0
puts

# Each bus gets an independent config snapshot — mutating one does not
# affect the global or other buses.

# ─── Tier 3: Channel-Level Overrides ─────────────────────────────────

puts "=== Tier 3: Channel-Level Overrides ==="
puts

bus = TypedBus::MessageBus.new(timeout: 30, max_pending: 100, throttle: 0.5)
puts "Bus defaults: timeout=30, max_pending=100, throttle=0.5"
puts

# Channel that inherits everything from its bus
bus.add_channel(:orders, type: String)
puts ":orders — inherits all bus defaults"

# Channel that overrides timeout only
bus.add_channel(:alerts, timeout: 2)
puts ":alerts — timeout=2, rest inherited"

# Channel that overrides max_pending and throttle
bus.add_channel(:logs, max_pending: 1000, throttle: 0.8)
puts ":logs   — max_pending=1000, throttle=0.8, timeout inherited"

# Channel that disables throttle (explicit 0.0 overrides bus's 0.5)
bus.add_channel(:metrics, max_pending: nil, throttle: 0.0)
puts ":metrics — unbounded, no throttle"
puts

# ─── Live Demo: Cascade in Action ────────────────────────────────────

puts "=== Live Demo ==="
puts

# Quiet logger for the demo
TypedBus.logger = nil

demo_bus = TypedBus::MessageBus.new(timeout: 0.05)
demo_bus.add_channel(:fast)            # inherits 0.05s timeout
demo_bus.add_channel(:slow, timeout: 5) # overrides to 5s

# :fast will auto-nack (subscriber never acks, 0.05s timeout)
demo_bus.subscribe(:fast) { |_d| }

# :slow will ack normally
demo_bus.subscribe(:slow) { |d| d.ack! }

Async do
  demo_bus.publish(:fast, "this will time out")
  demo_bus.publish(:slow, "this will be acked")
  sleep 0.1 # let the fast timeout fire
end

puts ":fast stats (inherited 0.05s timeout → timed out):"
puts "  published:     #{demo_bus.stats[:fast_published]}"
puts "  timed_out:     #{demo_bus.stats[:fast_timed_out]}"
puts "  dead_lettered: #{demo_bus.stats[:fast_dead_lettered]}"
puts
puts ":slow stats (overridden to 5s timeout → acked in time):"
puts "  published:     #{demo_bus.stats[:slow_published]}"
puts "  delivered:     #{demo_bus.stats[:slow_delivered]}"
puts

# ─── Reset ────────────────────────────────────────────────────────────

puts "=== Reset ==="
puts

# TypedBus.reset_configuration! restores factory defaults — handy in tests.
TypedBus.reset_configuration!
puts "After reset:"
puts "  timeout:     #{TypedBus.configuration.timeout}"       # => 30
puts "  max_pending: #{TypedBus.configuration.max_pending.inspect}" # => nil
puts "  throttle:    #{TypedBus.configuration.throttle}"       # => 0.0
puts "  logger:      #{TypedBus.configuration.logger.inspect}" # => nil
puts "  log_level:   #{TypedBus.configuration.log_level} (INFO)" # => 1
