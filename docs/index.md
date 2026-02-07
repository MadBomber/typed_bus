# TypedBus

Async pub/sub message bus with typed channels, ACK-based delivery, and dead letter queues for Ruby.

Built on the [async](https://github.com/socketry/async) gem with fiber-only concurrency. No mutexes, no threads. All state lives within a single Async reactor.

## Features

- **Typed channels** — constrain messages to a specific class; mismatches raise at the publish site
- **Explicit acknowledgment** — subscribers must `ack!` or `nack!` each delivery
- **Dead letter queues** — failed and timed-out deliveries collect for inspection or retry
- **Backpressure** — bounded channels block publishers when capacity is reached
- **Adaptive throttling** — asymptotic backoff slows publishers as channels fill
- **Three-tier configuration** — global, bus, and channel-level defaults with cascading inheritance
- **Per-channel stats** — published, delivered, nacked, timed_out, dead_lettered, throttled
- **Structured logging** — optional Ruby Logger integration across all components

## Quick Example

```ruby
require "typed_bus"

TypedBus.configure do |config|
  config.timeout   = 10
  config.log_level = Logger::INFO
end

bus = TypedBus::MessageBus.new
bus.add_channel(:events, type: String)

bus.subscribe(:events) do |delivery|
  puts delivery.message
  delivery.ack!
end

Async do
  bus.publish(:events, "hello world")
end
```

## Requirements

- Ruby >= 3.2.0
- [async](https://github.com/socketry/async) ~> 2.0

## License

MIT
