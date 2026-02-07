#!/usr/bin/env ruby
# frozen_string_literal: true

# 03 — Multiple Subscribers (Fan-Out)
#
# Every subscriber receives its own Delivery for each published message.
# A message is only considered "delivered" when ALL subscribers ack.

require_relative "../lib/typed_bus"

channel = TypedBus::Channel.new(:notifications, timeout: 5)

# Subscriber A — email sender
channel.subscribe do |delivery|
  puts "[Email]   Sending notification: #{delivery.message}"
  delivery.ack!
end

# Subscriber B — push notification
channel.subscribe do |delivery|
  puts "[Push]    Sending notification: #{delivery.message}"
  delivery.ack!
end

# Subscriber C — audit log
channel.subscribe do |delivery|
  puts "[Audit]   Logging: #{delivery.message}"
  delivery.ack!
end

puts "Subscribers: #{channel.subscriber_count}"
puts

Async do
  tracker = channel.publish("User signed in")

  # Yield to let subscriber fibers run and ack
  sleep(0)

  puts
  puts "Fully delivered? #{tracker.fully_delivered?}"
  puts "All resolved?    #{tracker.fully_resolved?}"
  puts "Pending count:   #{tracker.pending_count}"
end
