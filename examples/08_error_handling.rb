#!/usr/bin/env ruby
# frozen_string_literal: true

# 08 — Error Handling & Lifecycle
#
# Demonstrates how the library handles edge cases:
# - Subscriber exceptions are caught and auto-nacked
# - Publishing to a closed channel raises
# - Unsubscribing removes a subscriber mid-stream
# - Publishing with no subscribers routes to DLQ
# - close force-nacks all pending deliveries

require_relative "../lib/typed_bus"

bus = TypedBus::MessageBus.new
bus.add_channel(:events, timeout: 1)

# --- Subscriber errors are caught ---

puts "=== Subscriber Errors ==="
bus.subscribe(:events) do |delivery|
  raise "database connection lost!" if delivery.message == "crash"

  puts "  Processed: #{delivery.message}"
  delivery.ack!
end

Async do
  bus.publish(:events, "good message")
  bus.publish(:events, "crash")
  bus.publish(:events, "still works")
end

puts "  DLQ after errors: #{bus.dead_letters(:events).size} entries"
puts

# --- Publishing with no subscribers ---

puts "=== No Subscribers ==="
bus.add_channel(:orphan, timeout: 5)

Async { bus.publish(:orphan, "nobody home") }

puts "  DLQ: #{bus.dead_letters(:orphan).size} (message had no subscribers)"
puts

# --- Unsubscribe ---

puts "=== Unsubscribe ==="
bus.add_channel(:dynamic, timeout: 5)

received = []
sub_id = bus.subscribe(:dynamic) { |d| received << d.message; d.ack! }

Async { bus.publish(:dynamic, "before unsub") }
bus.unsubscribe(:dynamic, sub_id)
Async { bus.publish(:dynamic, "after unsub") }

puts "  Received: #{received.inspect}"
puts "  DLQ: #{bus.dead_letters(:dynamic).size} (second message had no subscriber)"
puts

# --- Close force-nacks pending deliveries ---

puts "=== Channel Close ==="
bus.add_channel(:closeable, timeout: 5)
bus.subscribe(:closeable) { |_d| } # never acks

Async do
  bus.publish(:closeable, "will be force-nacked")
  puts "  Pending before close: #{bus.pending_count(:closeable)}"
  bus.close(:closeable)
  puts "  Pending after close:  #{bus.pending_count(:closeable)}"
  puts "  DLQ after close:      #{bus.dead_letters(:closeable).size}"

  # Publishing to a closed channel raises
  begin
    bus.publish(:closeable, "too late")
  rescue RuntimeError => e
    puts "  Publish error: #{e.message}"
  end
end
