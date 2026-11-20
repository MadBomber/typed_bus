# Stats and Monitoring

`MessageBus` tracks per-channel counters automatically via a shared `Stats` instance.

## Available Counters

For each channel named `:orders`, the following counters are tracked:

| Counter | Description |
|---------|-------------|
| `:orders_published` | Messages `MessageBus#publish` accepted (a publish to an already-closed channel or with the wrong type raises and is not counted) |
| `:orders_delivered` | All subscribers ACKed (message fully delivered) |
| `:orders_nacked` | Nacks of any cause: `nack!`, a raising handler, `close`, or a publish with no subscribers (timeouts are counted separately) |
| `:orders_timed_out` | Delivery timeouts (auto-nack) |
| `:orders_dead_lettered` | Entries added to the DLQ |
| `:orders_throttled` | Publishes that were rate-limited |

`published` and `delivered` count once per message. `nacked`, `timed_out` and
`dead_lettered` count once per subscriber delivery, so one publish to a channel
with three subscribers can add up to 3 to each of them.

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

stats[:work_delivered]  # => N
```

A bare `Channel` records `delivered`, `nacked`, `timed_out`, `dead_lettered`
and `throttled`. It does not record `published`: that counter is incremented
by `MessageBus#publish`, so `stats[:work_published]` stays `0` here.

## Monitoring Pattern

Combine stats with DLQ callbacks for real-time alerting. Because
`dead_lettered` counts per subscriber delivery and `published` counts per
message, their ratio is dead letters per publish, which can exceed 1 when a
channel has several subscribers:

```ruby
bus.add_channel(:orders, timeout: 10)

bus.dead_letters(:orders).on_dead_letter do |delivery|
  per_publish = bus.stats[:orders_dead_lettered].to_f / bus.stats[:orders_published]
  if per_publish > 0.1
    alert("Orders dead letters per publish above 0.1: #{per_publish.round(2)}")
  end
end
```
