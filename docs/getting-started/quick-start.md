# Quick Start

## Minimal Example

```ruby
require "typed_bus"

bus = TypedBus::MessageBus.new
bus.add_channel(:events, timeout: 5)

bus.subscribe(:events) do |delivery|
  puts "Received: #{delivery.message}"
  delivery.ack!
end

Async do
  bus.publish(:events, "hello world")
end
```

## What Just Happened

1. **Created a bus** — `MessageBus.new` creates a registry for channels with shared stats.
2. **Added a channel** — `:events` is a named topic with a 5-second delivery timeout.
3. **Subscribed** — the block receives a `Delivery` envelope for each published message. The subscriber must call `ack!` or `nack!`.
4. **Published inside Async** — channel operations create Async tasks internally, so `publish` must run within an Async reactor.

## Using Channels Directly

You don't need a MessageBus. Channels work standalone:

```ruby
require "typed_bus"

channel = TypedBus::Channel.new(:greetings, timeout: 5)

channel.subscribe do |delivery|
  puts delivery.message
  delivery.ack!
end

Async do
  channel.publish("Hello, world!")
end
```

## Next Steps

- [Configuration](configuration.md) — set defaults at global, bus, and channel levels
- [Typed Channels](../guides/typed-channels.md) — constrain messages to a specific class
- [Delivery and Acknowledgment](../guides/delivery-and-ack.md) — understand ack/nack lifecycle
