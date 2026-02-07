# TypedBus
<em>Async pub/sub with typed channels and ACK-based delivery</em>

<table>
<tr>
<td width="50%" align="center" valign="top">
<img src="docs/assets/images/typed_bus.gif" alt="TypedBus" width="438"><br>
<a href="https://madbomber.github.io/typed_bus">Comprehensive Documentation</a>
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

## Installation

Add to your Gemfile:

```ruby
gem "typed_bus"
```

Then run:

```bash
bundle install
```

## Quick Start

```ruby
require "typed_bus"

bus = TypedBus::MessageBus.new
bus.add_channel(:events, timeout: 5)

bus.subscribe(:events) do |delivery|
  puts delivery.message
  delivery.ack!
end

Async do
  bus.publish(:events, "hello world")
end
```

## Channels

A channel is a named pub/sub topic. Subscribers receive `Delivery` envelopes and must call `ack!` or `nack!`.

```ruby
channel = TypedBus::Channel.new(:orders, timeout: 10)
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | `Class` | `nil` | Restricts published messages to a specific class |
| `timeout` | `Numeric` | `30` | Seconds before unresolved deliveries auto-nack |
| `max_pending` | `Integer` | `nil` | Backpressure limit; `nil` = unbounded |
| `throttle` | `Float` | `0.0` | Remaining-capacity ratio where backoff begins; `0.0` = disabled |

### Typed Channels

Restrict a channel to a single message class:

```ruby
channel = TypedBus::Channel.new(:orders, type: Order)

Async do
  channel.publish(Order.new)   # OK
  channel.publish("not valid") # raises ArgumentError
end
```

### Subscribe and Unsubscribe

```ruby
id = channel.subscribe do |delivery|
  process(delivery.message)
  delivery.ack!
end

channel.unsubscribe(id)
```

### Publish

```ruby
Async do
  tracker = channel.publish(my_message)
  # tracker is a DeliveryTracker (nil if no subscribers)
end
```

## Delivery

Each subscriber receives a `Delivery` envelope wrapping the published message. The subscriber must resolve it:

```ruby
channel.subscribe do |delivery|
  delivery.message    # the published object
  delivery.channel_name
  delivery.subscriber_id

  delivery.ack!       # mark as successfully processed
  # or
  delivery.nack!      # mark as failed (routes to dead letter queue)
end
```

If neither `ack!` nor `nack!` is called before the channel's `timeout`, the delivery auto-nacks.

### Delivery States

| Method | Description |
|--------|-------------|
| `pending?` | Not yet resolved |
| `acked?` | Successfully acknowledged |
| `nacked?` | Explicitly rejected or timed out |
| `timed_out?` | True if the nack was caused by timeout |

## Dead Letter Queue

Every channel has a dead letter queue that collects failed deliveries (nacked or timed out).

```ruby
channel.dead_letter_queue.size
channel.dead_letter_queue.empty?

# Iterate without removing
channel.dead_letter_queue.each do |delivery|
  puts "#{delivery.message} failed on subscriber ##{delivery.subscriber_id}"
end

# Drain and reprocess
channel.dead_letter_queue.drain do |delivery|
  retry_message(delivery.message)
end
```

Messages published with no subscribers are also routed to the DLQ.

### DLQ Callback

```ruby
channel.dead_letter_queue.on_dead_letter do |delivery|
  alert("Dead letter: #{delivery.message}")
end
```

## Backpressure

Set `max_pending` to bound how many unresolved deliveries a channel allows. When the limit is reached, `publish` blocks the calling fiber until subscribers ack.

```ruby
channel = TypedBus::Channel.new(:work,
  max_pending: 100,
  timeout: 10
)
```

## Adaptive Throttling

When a bounded channel approaches capacity, adaptive throttling progressively slows publishers before they hit the hard block.

Set `throttle` to a `Float` between `0.0` (exclusive) and `1.0` (exclusive). The value is the remaining-capacity ratio at which backoff begins. Below that threshold, each publish sleeps for `1 / (max_pending * remaining_ratio)` seconds.

```ruby
channel = TypedBus::Channel.new(:pipeline,
  max_pending: 10,
  throttle: 0.5   # begin backoff at 50% remaining capacity
)
```

### Backoff Curve

With `max_pending: 10, throttle: 0.5`:

```
Publish  Pending  Remaining  Ratio  Delay
───────────────────────────────────────────
  1        0        10       1.0    —
  2        1         9       0.9    —
  3        2         8       0.8    —
  4        3         7       0.7    —
  5        4         6       0.6    —
  6        5         5       0.5    0.200s
  7        6         4       0.4    0.250s
  8        7         3       0.3    0.333s
  9        8         2       0.2    0.500s
 10        9         1       0.1    1.000s
 11       10         0       0.0    hard block
```

The first 50% of capacity fills at full speed. The last 50% applies an asymptotic delay that approaches infinity as remaining capacity approaches zero. At zero remaining, the existing `wait_for_capacity` hard-blocks until a subscriber acks.

Higher `throttle` values begin backoff earlier:

```ruby
TypedBus::Channel.new(:conservative, max_pending: 100, throttle: 0.8)  # backoff at 80% remaining
TypedBus::Channel.new(:aggressive,   max_pending: 100, throttle: 0.3)  # backoff at 30% remaining
```

## Configuration

TypedBus resolves parameters through a three-tier cascade: **Global → Bus → Channel**. Each tier inherits from the one above unless explicitly overridden.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | `30` | Delivery ACK deadline in seconds |
| `max_pending` | `nil` | Backpressure limit; `nil` = unbounded |
| `throttle` | `0.0` | Remaining-capacity ratio where backoff begins; `0.0` = disabled |
| `logger` | `nil` | Ruby Logger instance (global-only) |
| `log_level` | `Logger::INFO` | Log level applied to the logger (global-only) |

### Global Defaults

```ruby
TypedBus.configure do |config|
  config.timeout     = 60
  config.max_pending = 500
  config.throttle    = 0.5
  config.logger      = Logger.new($stdout)
  config.log_level   = Logger::DEBUG
end
```

### Cascade Example

```ruby
# Global: timeout=60, max_pending=500
TypedBus.configure do |config|
  config.timeout     = 60
  config.max_pending = 500
end

# Bus overrides timeout, inherits max_pending
bus = TypedBus::MessageBus.new(timeout: 30)

# Channel inherits both from bus (timeout=30, max_pending=500)
bus.add_channel(:orders)

# Channel overrides timeout, inherits max_pending from bus
bus.add_channel(:alerts, timeout: 5)
```

### Reset

Restore factory defaults (useful in tests):

```ruby
TypedBus.reset_configuration!
```

## MessageBus

`MessageBus` is a registry facade that manages multiple named channels with shared stats.

```ruby
bus = TypedBus::MessageBus.new
bus.add_channel(:orders, type: Order, max_pending: 100, timeout: 10)
bus.add_channel(:alerts, type: String)

bus.subscribe(:orders) { |d| process(d.message); d.ack! }
bus.subscribe(:alerts) { |d| log(d.message); d.ack! }

Async do
  bus.publish(:orders, Order.new)
  bus.publish(:alerts, "system ok")
end
```

### Bus-Level Defaults

Pass `timeout`, `max_pending`, or `throttle` to the constructor to set defaults for all channels on this bus:

```ruby
bus = TypedBus::MessageBus.new(timeout: 10, max_pending: 200, throttle: 0.5)

# Inherits all bus defaults
bus.add_channel(:orders, type: Order)

# Overrides throttle, inherits timeout and max_pending
bus.add_channel(:alerts, throttle: 0.3)

# Disables throttle for this channel
bus.add_channel(:logs, throttle: 0.0)
```

### Bus Methods

| Method | Description |
|--------|-------------|
| `add_channel(name, **opts)` | Register a named channel |
| `remove_channel(name)` | Close and remove a channel |
| `publish(name, message)` | Publish to a named channel |
| `subscribe(name, &block)` | Subscribe to a named channel |
| `unsubscribe(name, id)` | Remove a subscriber |
| `pending?(name)` | Check for unresolved deliveries |
| `pending_count(name)` | Count unresolved deliveries |
| `dead_letters(name)` | Access a channel's DLQ |
| `close(name)` | Close a specific channel |
| `close_all` | Close all channels |
| `channel?(name)` | Check if a channel exists |
| `channel_names` | List registered channel names |
| `clear!` | Reset all channels and stats |
| `stats` | Access the shared Stats object |

## Stats

`MessageBus` tracks per-channel counters automatically:

```ruby
bus.stats[:orders_published]     # messages published
bus.stats[:orders_delivered]     # all subscribers acked
bus.stats[:orders_nacked]        # explicit nacks
bus.stats[:orders_timed_out]     # delivery timeouts
bus.stats[:orders_dead_lettered] # entries added to DLQ
bus.stats[:orders_throttled]     # publishes that were rate-limited

bus.stats.to_h                   # snapshot of all counters
bus.stats.reset!                 # zero all counters
```

When using `Channel` directly, pass a `Stats` instance:

```ruby
stats = TypedBus::Stats.new
channel = TypedBus::Channel.new(:work, stats: stats, timeout: 5)
```

## Logging

Assign a standard Ruby `Logger` to get structured log output from all components:

```ruby
TypedBus.configure do |config|
  config.logger = Logger.new($stdout)
end

# or use the shortcut
TypedBus.logger = Logger.new($stdout)
```

Set to `nil` (the default) to disable logging.

Log output covers channel lifecycle, publish/subscribe events, delivery resolution, DLQ entries, backpressure waits, and throttle delays.

## Closing and Cleanup

### Close a Channel

Stops accepting new publishes and subscribes. Pending deliveries are force-nacked and routed to the DLQ.

```ruby
channel.close
channel.closed?  # => true
```

### Clear a Channel

Hard reset: cancels all timeout tasks, discards pending state and DLQ contents.

```ruby
channel.clear!
```

### Bus Shutdown

```ruby
bus.close_all   # close every channel
bus.clear!      # close, clear DLQs, and reset stats
```

## Architecture

```
Publisher
    │
    ▼
Channel (type check → throttle → backpressure → fan-out)
    │
    ├──▶ Subscriber 1 ──▶ Delivery ──▶ ack!/nack!
    ├──▶ Subscriber 2 ──▶ Delivery ──▶ ack!/nack!
    └──▶ Subscriber N ──▶ Delivery ──▶ ack!/nack!
    │
    ▼
DeliveryTracker (aggregates N responses)
    │
    ├── all acked ──▶ :delivered stat
    └── any nacked ──▶ Dead Letter Queue
```

**Concurrency model:** Fiber-only, powered by the `async` gem. No mutexes anywhere. All state is managed within a single Async reactor. `sleep` calls inside throttle and backpressure yield the fiber, not the thread.

## Requirements

- Ruby >= 3.2.0
- [async](https://github.com/socketry/async) ~> 2.0

## License

MIT
