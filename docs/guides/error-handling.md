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
# => ArgumentError: Unknown channel: :nonexistent (registered: :orders)

bus.subscribe("orders") { |d| d.ack! }
# => ArgumentError: Unknown channel: "orders" (registered: :orders)
```

The message shows the name you passed with `inspect` and lists the registered
channel names, so a String/Symbol mix-up (`"orders"` vs `:orders`) is easy to
spot. A bus with no channels says `(no channels registered)`.

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

- `throttle` without `max_pending` raises `ArgumentError` when the channel is created
- `throttle` that is not `nil`, `0`, or a number strictly between `0` and `1` raises `ArgumentError` as soon as it is set: in `Configuration#throttle=`, `MessageBus.new`, `add_channel`, or `Channel.new`

```ruby
TypedBus::Channel.new(:bad, throttle: 0.5, timeout: 5)
# => ArgumentError: throttle requires max_pending on channel :bad

TypedBus::MessageBus.new(throttle: 1.5, max_pending: 10)
# => ArgumentError: throttle must be 0 (off) or between 0.0 and 1.0 (exclusive), got 1.5
```

## max_pending Validation

`max_pending` must be `nil` (unbounded) or a positive `Integer`. `Configuration#max_pending=`, `MessageBus.new`, `add_channel`, and `Channel.new` raise `ArgumentError` for anything else:

```ruby
TypedBus::Channel.new(:bad, max_pending: 0)
# => ArgumentError: max_pending must be nil or a positive Integer, got 0
```

## Type Validation

A channel's `type:` must be a `Class` or `Module` (or `nil` for untyped). Anything else raises `ArgumentError` when the channel is created:

```ruby
TypedBus::Channel.new(:bad, type: "Order")
# => ArgumentError: type must be a Class or Module, got "Order" on channel :bad
```

## Subscribing Without a Block

`subscribe` needs a block to deliver to. Calling it without one raises `ArgumentError`:

```ruby
bus.subscribe(:orders)
# => ArgumentError: Channel :orders subscribe requires a block
```

## Raising Dead Letter Callbacks

An `on_dead_letter` callback runs inside the nack that dead-lettered the delivery. If it raises, the entry is already in the DLQ and the `nacked`/`timed_out` and `dead_lettered` stats are already counted, but the error propagates to whoever triggered the nack: the subscriber (where it is logged as a subscriber error), the timeout task, or the publisher when there are no subscribers. Rescue inside the callback if it can fail.
