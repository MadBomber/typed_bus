#!/usr/bin/env ruby
# frozen_string_literal: true

# 01 — Basic Pub/Sub with Acknowledgment
#
# The simplest use case: one channel, one subscriber, explicit ack.
# Every subscriber receives a Delivery envelope and must call ack! or nack!
# to confirm receipt.

require_relative "../lib/typed_bus"

channel = TypedBus::Channel.new(:greetings, timeout: 5)

channel.subscribe do |delivery|
  puts "Received: #{delivery.message}"
  delivery.ack!
  puts "  -> acknowledged"
end

Async do
  channel.publish("Hello, world!")
  channel.publish("Goodbye, world!")
end

puts
puts "All messages delivered and acknowledged."
