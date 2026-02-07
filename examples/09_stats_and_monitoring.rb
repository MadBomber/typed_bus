#!/usr/bin/env ruby
# frozen_string_literal: true

# 09 — Stats & Monitoring
#
# The MessageBus tracks per-channel counters automatically:
#   - :channel_published  — messages sent
#   - :channel_delivered   — all subscribers acked
#   - :channel_nacked      — explicitly rejected
#   - :channel_timed_out   — deadline exceeded
#   - :channel_dead_lettered — routed to DLQ (nack + timeout + no-subscriber)
#
# Combine with DLQ callbacks for real-time alerting.

require_relative "../lib/typed_bus"

bus = TypedBus::MessageBus.new
bus.add_channel(:payments, timeout: 0.2)

# DLQ callback for alerting
bus.dead_letters(:payments).on_dead_letter do |delivery|
  status = delivery.timed_out? ? "TIMEOUT" : "REJECTED"
  $stderr.puts "  ** ALERT ** [#{status}] payment failed: #{delivery.message.inspect}"
end

# Subscriber that rejects large payments and ignores some (timeout)
bus.subscribe(:payments) do |delivery|
  amount = delivery.message[:amount]

  if amount > 500
    delivery.nack!
  elsif amount < 10
    # "forget" to ack — will timeout
  else
    delivery.ack!
  end
end

puts "Processing payments..."
puts

Async do
  [25, 750, 5, 100, 1200, 8, 50].each do |amount|
    bus.publish(:payments, { id: rand(1000..9999), amount: amount })
  end

  # Wait for timeouts
  sleep(0.4)
end

puts
puts "--- Payment Channel Stats ---"

stats = bus.stats
%i[published delivered nacked timed_out dead_lettered].each do |metric|
  key = :"payments_#{metric}"
  puts "  #{metric}: #{stats[key]}"
end

puts
puts "--- DLQ Contents (#{bus.dead_letters(:payments).size} entries) ---"

bus.dead_letters(:payments).each do |dead|
  reason = dead.timed_out? ? "timeout" : "nack"
  puts "  Payment ##{dead.message[:id]}: $#{dead.message[:amount]} (#{reason})"
end

# Stats can be reset for a new monitoring window
bus.stats.reset!
puts
puts "Stats after reset: #{bus.stats.to_h.inspect}"
