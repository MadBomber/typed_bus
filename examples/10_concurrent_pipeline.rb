#!/usr/bin/env ruby
# frozen_string_literal: true

# 10 — Concurrent Pipeline
#
# Combines everything into a realistic scenario: an event-driven pipeline
# with multiple stages, typed messages, backpressure, timeout handling,
# DLQ monitoring, and graceful shutdown.
#
# Pipeline:
#   [Ingest] -> :raw_events -> [Validate] -> :validated -> [Process] -> done
#                                   |                          |
#                                  nack                     timeout
#                                   v                          v
#                                  DLQ                        DLQ

require_relative "../lib/typed_bus"

RawEvent       = Data.define(:source, :payload, :timestamp)
ValidatedEvent = Data.define(:source, :payload, :validated_at)

bus = TypedBus::MessageBus.new

bus.add_channel(:raw_events, type: RawEvent,       timeout: 1, max_pending: 3)
bus.add_channel(:validated,  type: ValidatedEvent,  timeout: 0.3)

# --- Stage 1: Validation ---

bus.subscribe(:raw_events) do |delivery|
  event = delivery.message

  if event.payload.nil? || event.payload.empty?
    puts "  [Validate] REJECTED empty payload from #{event.source}"
    delivery.nack!
  else
    puts "  [Validate] OK: #{event.source} -> #{event.payload}"
    delivery.ack!

    # Forward to next stage
    validated = ValidatedEvent.new(
      source: event.source,
      payload: event.payload,
      validated_at: Time.now
    )
    bus.publish(:validated, validated)
  end
end

# --- Stage 2: Processing ---

bus.subscribe(:validated) do |delivery|
  event = delivery.message

  # Simulate slow processing for some events
  if event.payload.include?("slow")
    puts "  [Process]  Starting slow work: #{event.payload}..."
    sleep(0.5) # exceeds 0.3s timeout
    # Will never reach ack! — timeout fires first
  else
    puts "  [Process]  Completed: #{event.payload}"
    delivery.ack!
  end
end

# --- DLQ monitoring ---

%i[raw_events validated].each do |ch|
  bus.dead_letters(ch).on_dead_letter do |dead|
    reason = dead.timed_out? ? "TIMEOUT" : "NACK"
    puts "  [DLQ:#{ch}] #{reason}: #{dead.message.inspect}"
  end
end

# --- Produce events ---

puts "=== Pipeline Start ==="
puts

events = [
  RawEvent.new(source: "web",    payload: "user.signup",  timestamp: Time.now),
  RawEvent.new(source: "api",    payload: "",             timestamp: Time.now),
  RawEvent.new(source: "mobile", payload: "order.placed", timestamp: Time.now),
  RawEvent.new(source: "web",    payload: "slow.export",  timestamp: Time.now),
  RawEvent.new(source: "api",    payload: "user.login",   timestamp: Time.now),
  RawEvent.new(source: "batch",  payload: nil.to_s,       timestamp: Time.now),
]

Async do
  events.each_with_index do |event, i|
    puts "[Ingest ##{i}] #{event.source}: #{event.payload.inspect}"
    bus.publish(:raw_events, event)
  end

  # Wait for timeouts to resolve
  sleep(0.6)
end

# --- Final report ---

puts
puts "=== Pipeline Report ==="
puts

stats = bus.stats
%i[raw_events validated].each do |ch|
  puts "#{ch}:"
  %i[published delivered nacked timed_out dead_lettered].each do |m|
    val = stats[:"#{ch}_#{m}"]
    puts "  #{m}: #{val}" if val > 0
  end
  puts "  DLQ size: #{bus.dead_letters(ch).size}"
  puts
end

bus.close_all
puts "All channels closed."
