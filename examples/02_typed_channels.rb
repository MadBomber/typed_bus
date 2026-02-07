#!/usr/bin/env ruby
# frozen_string_literal: true

# 02 — Typed Channels
#
# Channels can enforce a type constraint. Publishing the wrong type raises
# immediately, catching bugs at the publish site rather than in subscribers.

require_relative "../lib/typed_bus"

# Define domain events using Ruby's Data class
UserRegistered = Data.define(:email, :plan)
OrderPlaced    = Data.define(:order_id, :total)

# This channel only accepts UserRegistered messages
channel = TypedBus::Channel.new(:users, type: UserRegistered, timeout: 5)

channel.subscribe do |delivery|
  event = delivery.message
  puts "New user: #{event.email} (#{event.plan} plan)"
  delivery.ack!
end

Async do
  # This works — correct type
  channel.publish(UserRegistered.new(email: "alice@example.com", plan: :pro))

  # This raises ArgumentError — wrong type
  begin
    channel.publish(OrderPlaced.new(order_id: 42, total: 99.99))
  rescue ArgumentError => e
    puts "\nType violation caught: #{e.message}"
  end

  # Plain strings are also rejected
  begin
    channel.publish("not a UserRegistered")
  rescue ArgumentError => e
    puts "Type violation caught: #{e.message}"
  end
end
