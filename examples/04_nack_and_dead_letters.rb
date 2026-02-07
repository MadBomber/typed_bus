#!/usr/bin/env ruby
# frozen_string_literal: true

# 04 — Explicit NACK and Dead Letter Queue
#
# Subscribers can reject messages with nack!. Rejected deliveries are
# routed to the channel's dead letter queue for later inspection or retry.

require_relative "../lib/typed_bus"

channel = TypedBus::Channel.new(:orders, timeout: 5)

channel.subscribe do |delivery|
  order = delivery.message

  if order[:total] > 1000
    puts "REJECTED order ##{order[:id]} — amount $#{order[:total]} exceeds limit"
    delivery.nack!
  else
    puts "Processed order ##{order[:id]} — $#{order[:total]}"
    delivery.ack!
  end
end

Async do
  channel.publish({ id: 1, total: 50 })
  channel.publish({ id: 2, total: 2500 })
  channel.publish({ id: 3, total: 150 })
  channel.publish({ id: 4, total: 9999 })
end

puts
puts "--- Dead Letter Queue (#{channel.dead_letter_queue.size} entries) ---"

channel.dead_letter_queue.each do |dead|
  puts "  Failed: order ##{dead.message[:id]} ($#{dead.message[:total]})"
  puts "    channel: #{dead.channel_name}, nacked: #{dead.nacked?}, timed_out: #{dead.timed_out?}"
end

# Drain removes entries from the DLQ while yielding them
puts
puts "Draining DLQ for retry..."
channel.dead_letter_queue.drain do |dead|
  puts "  Retrying order ##{dead.message[:id]}..."
end

puts "DLQ now empty: #{channel.dead_letter_queue.empty?}"
