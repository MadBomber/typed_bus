# TypedBus
<em>Async pub/sub with typed channels and ACK-based delivery</em>

<table>
<tr>
<td width="50%" align="center" valign="top">
<img src="assets/images/typed_bus.gif" alt="TypedBus" width="875"><br>
<a href="https://github.com/madbomber/typed_bus">GitHub Repository</a>
</td>
<td width="50%" valign="top">
TypedBus provides named, optionally typed pub/sub channels with explicit ACK/NACK delivery, dead letter queues, backpressure, and adaptive throttling — all within a single Async reactor.<br><br>
<strong>Key Features</strong><br>

- <strong>Typed Channels</strong> - Restrict messages to a specific class<br>
- <strong>ACK-Based Delivery</strong> - Subscribers must explicitly ack or nack<br>
- <strong>Dead Letter Queues</strong> - Collect nacked and timed-out deliveries<br>
- <strong>Backpressure</strong> - Bound pending deliveries per channel<br>
- <strong>Adaptive Throttling</strong> - Progressive slowdown as capacity fills<br>
- <strong>Configuration Cascade</strong> - Global → Bus → Channel defaults<br>
- <strong>Stats Tracking</strong> - Per-channel publish/deliver/nack/timeout counters<br>
- <strong>Structured Logging</strong> - Optional Logger integration across all components
</td>
</tr>
</table>

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
