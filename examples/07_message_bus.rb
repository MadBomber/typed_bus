#!/usr/bin/env ruby
# frozen_string_literal: true

# 07 — MessageBus Facade
#
# MessageBus is a registry that manages multiple named channels.
# It provides a single entry point for publish, subscribe, stats,
# dead letter access, and lifecycle management.

require_relative "../lib/typed_bus"

UserEvent = Data.define(:action, :user)
OrderEvent = Data.define(:action, :order_id, :total)

bus = TypedBus::MessageBus.new

# Register typed channels
bus.add_channel(:users,  type: UserEvent,  timeout: 5)
bus.add_channel(:orders, type: OrderEvent, timeout: 5)

# Subscribe to user events
bus.subscribe(:users) do |delivery|
  event = delivery.message
  puts "[Users]  #{event.action}: #{event.user}"
  delivery.ack!
end

# Subscribe to order events — two subscribers
bus.subscribe(:orders) do |delivery|
  event = delivery.message
  puts "[Orders] #{event.action}: order ##{event.order_id} ($#{event.total})"
  delivery.ack!
end

bus.subscribe(:orders) do |delivery|
  event = delivery.message
  puts "[Audit]  #{event.action}: order ##{event.order_id}"
  delivery.ack!
end

puts "Channels: #{bus.channel_names.inspect}"
puts

Async do
  bus.publish(:users, UserEvent.new(action: "registered", user: "alice"))
  bus.publish(:users, UserEvent.new(action: "logged_in",  user: "bob"))
  bus.publish(:orders, OrderEvent.new(action: "placed",  order_id: 101, total: 49.99))
  bus.publish(:orders, OrderEvent.new(action: "shipped", order_id: 101, total: 49.99))
end

puts
puts "--- Stats ---"
bus.stats.to_h.each do |key, value|
  puts "  #{key}: #{value}"
end
