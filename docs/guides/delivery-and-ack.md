# Delivery and Acknowledgment

Every subscriber receives a `Delivery` envelope wrapping the published message. The subscriber must explicitly resolve the delivery.

## The Delivery Envelope

```ruby
channel.subscribe do |delivery|
  delivery.message        # the published object
  delivery.channel_name   # :orders
  delivery.subscriber_id  # integer ID assigned at subscribe time

  delivery.ack!           # success
  # or
  delivery.nack!          # failure → routes to dead letter queue
end
```

## Acknowledgment Rules

- Each delivery must be resolved exactly once with `ack!` or `nack!`
- Calling `ack!` or `nack!` a second time raises `RuntimeError`
- If neither is called before the channel's `timeout`, the delivery auto-nacks

## Delivery States

| Method | Description |
|--------|-------------|
| `pending?` | Not yet resolved |
| `acked?` | Successfully acknowledged |
| `nacked?` | Explicitly rejected or timed out |
| `timed_out?` | `true` if the nack was caused by timeout |

## Timeout Behavior

When a delivery times out:

1. `timed_out?` returns `true`
2. The delivery is automatically NACKed
3. It routes to the dead letter queue
4. The `:timed_out` and `:dead_lettered` stats increment

```ruby
channel = TypedBus::Channel.new(:work, timeout: 2)

channel.subscribe do |delivery|
  sleep 5  # exceeds the 2s timeout
  delivery.ack!  # raises — already resolved by timeout
end
```

Use `timed_out?` to distinguish timeouts from explicit nacks when processing the DLQ:

```ruby
channel.dead_letter_queue.each do |delivery|
  if delivery.timed_out?
    # retry — subscriber was too slow
  else
    # investigate — subscriber explicitly rejected
  end
end
```

## Multiple Subscribers

When a message has multiple subscribers, each gets its own independent Delivery:

```ruby
bus.add_channel(:events, timeout: 5)
bus.subscribe(:events) { |d| d.ack! }      # subscriber 1
bus.subscribe(:events) { |d| d.nack! }     # subscriber 2
```

The message is "delivered" (`:delivered` stat) only when **all** subscribers ACK. If any subscriber NACKs, only that subscriber's Delivery goes to the DLQ.

## DeliveryTracker

`publish` returns a `DeliveryTracker` that aggregates subscriber responses:

```ruby
Async do
  tracker = channel.publish(message)
  # tracker.fully_delivered?  — all acked?
  # tracker.fully_resolved?   — all responded?
  # tracker.pending_count     — still waiting on N
end
```

Returns `nil` if there are no subscribers (message goes directly to DLQ).
