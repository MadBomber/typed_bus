# Stats and Monitoring

`MessageBus` tracks per-channel counters automatically via a shared `Stats` instance.

## Available Counters

For each channel named `:orders`, the following counters are tracked:

| Counter | Description |
|---------|-------------|
| `:orders_published` | Messages published |
| `:orders_delivered` | All subscribers ACKed (message fully delivered) |
| `:orders_nacked` | Explicit nacks by subscribers |
| `:orders_timed_out` | Delivery timeouts (auto-nack) |
| `:orders_dead_lettered` | Entries added to the DLQ |
| `:orders_throttled` | Publishes that were rate-limited |

## Reading Stats

```ruby
bus.stats[:orders_published]     # => 42
bus.stats[:orders_delivered]     # => 40
bus.stats[:orders_dead_lettered] # => 2
```

## Snapshot

Get all counters as a Hash:

```ruby
bus.stats.to_h
# => { orders_published: 42, orders_delivered: 40, ... }
```

## Reset

Zero all counters:

```ruby
bus.stats.reset!
```

Or reset everything (channels + stats):

```ruby
bus.clear!
```

## Using Stats Directly

When using `Channel` without a `MessageBus`, pass a `Stats` instance:

```ruby
stats = TypedBus::Stats.new
channel = TypedBus::Channel.new(:work, stats: stats, timeout: 5)

# ... publish and subscribe ...

stats[:work_published]  # => N
```

## Monitoring Pattern

Combine stats with DLQ callbacks for real-time alerting:

```ruby
bus.add_channel(:orders, timeout: 10)

bus.dead_letters(:orders).on_dead_letter do |delivery|
  error_rate = bus.stats[:orders_dead_lettered].to_f / bus.stats[:orders_published]
  if error_rate > 0.1
    alert("Orders DLQ error rate above 10%: #{(error_rate * 100).round}%")
  end
end
```
