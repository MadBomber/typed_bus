#!/usr/bin/env ruby
# frozen_string_literal: true

# 05 — Delivery Timeout
#
# Each delivery has a deadline. If a subscriber doesn't ack or nack
# within the timeout period, the delivery auto-nacks and lands in the DLQ.
# The timed_out? flag distinguishes timeouts from explicit nacks.

require_relative "../lib/typed_bus"

# Short timeout for demonstration
channel = TypedBus::Channel.new(:tasks, timeout: 0.3)

channel.subscribe do |delivery|
  task = delivery.message

  case task[:type]
  when :fast
    puts "[#{task[:name]}] Processing quickly..."
    delivery.ack!
  when :slow
    puts "[#{task[:name]}] Starting long operation... (will exceed timeout)"
    # Simulates work that takes longer than the 0.3s timeout.
    # The subscriber never acks — the timeout will auto-nack.
  end
end

Async do
  channel.publish({ type: :fast, name: "compile" })
  channel.publish({ type: :slow, name: "deploy" })
  channel.publish({ type: :fast, name: "notify" })
  channel.publish({ type: :slow, name: "backup" })

  # Wait for timeouts to fire
  sleep(0.5)
end

puts
puts "--- Dead Letter Queue ---"
channel.dead_letter_queue.each do |dead|
  status = dead.timed_out? ? "TIMED OUT" : "NACKED"
  puts "  [#{status}] #{dead.message[:name]}"
end
