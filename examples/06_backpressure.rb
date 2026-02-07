#!/usr/bin/env ruby
# frozen_string_literal: true

# 06 — Bounded Channels & Backpressure
#
# Setting max_pending limits how many unresolved deliveries can exist.
# When the limit is reached, the publishing fiber blocks until a delivery
# resolves. This prevents fast producers from overwhelming slow consumers.

require_relative "../lib/typed_bus"

# Only 2 deliveries can be in-flight at once
channel = TypedBus::Channel.new(:pipeline, timeout: 5, max_pending: 2)

channel.subscribe do |delivery|
  item = delivery.message
  puts "  [consumer] Processing #{item}... (pending: #{channel.pending_count})"
  sleep(0.1) # simulate work
  delivery.ack!
  puts "  [consumer] Done with #{item}"
end

Async do
  5.times do |i|
    puts "[producer] Publishing item_#{i} (pending before: #{channel.pending_count})"
    channel.publish("item_#{i}")
    puts "[producer] Published item_#{i}"
  end
end

puts
puts "All items processed. Pending: #{channel.pending_count}"
