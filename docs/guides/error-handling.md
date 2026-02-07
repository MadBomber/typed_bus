# Error Handling

TypedBus handles errors predictably at every level.

## Subscriber Exceptions

If a subscriber block raises, the delivery is auto-NACKed and routed to the DLQ:

```ruby
bus.subscribe(:orders) do |delivery|
  raise "something broke"
  # delivery is auto-nacked, exception is logged
end
```

The exception is rescued within the subscriber's Async task. Other subscribers and the channel continue operating normally.

## Type Mismatches

Publishing a message that doesn't match the channel's type raises `ArgumentError` at the publish site:

```ruby
bus.add_channel(:orders, type: Order)

Async do
  bus.publish(:orders, "not an order")
  # => ArgumentError: Expected Order, got String on channel :orders
end
```

## Unknown Channels

All MessageBus methods that take a channel name raise `ArgumentError` for unknown channels:

```ruby
bus.publish(:nonexistent, "msg")
# => ArgumentError: Unknown channel: nonexistent

bus.subscribe(:nonexistent) { |d| d.ack! }
# => ArgumentError: Unknown channel: nonexistent
```

`remove_channel` is the exception — it's a no-op for unknown channels.

## Publishing to a Closed Channel

```ruby
bus.close(:orders)
bus.publish(:orders, "msg")
# => RuntimeError: Channel :orders is closed
```

## Subscribing to a Closed Channel

```ruby
bus.close(:orders)
bus.subscribe(:orders) { |d| d.ack! }
# => RuntimeError: Channel :orders is closed
```

## Double Resolution

Calling `ack!` or `nack!` on an already-resolved delivery raises `RuntimeError`:

```ruby
bus.subscribe(:orders) do |delivery|
  delivery.ack!
  delivery.ack!   # => RuntimeError: Delivery already resolved as acked
end
```

## No Subscribers

Messages published with no subscribers go directly to the DLQ:

```ruby
bus.add_channel(:empty)
Async { bus.publish(:empty, "orphan") }

bus.dead_letters(:empty).size  # => 1
```

## Throttle Validation

- `throttle` without `max_pending` raises `ArgumentError`
- `throttle` outside `(0.0, 1.0)` raises `ArgumentError`

```ruby
TypedBus::Channel.new(:bad, throttle: 0.5, timeout: 5)
# => ArgumentError: throttle requires max_pending on channel :bad
```
