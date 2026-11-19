# Channel

`TypedBus::Channel`

A named, typed pub/sub channel with explicit acknowledgment tracking.

## Constructor

### `Channel.new(name, type:, timeout:, max_pending:, stats:, throttle:)`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `name` | required | `Symbol` channel name |
| `type` | `nil` | Optional `Class` or `Module` constraint for messages |
| `timeout` | `30` | Seconds before delivery auto-nacks; `nil` = never auto-nack |
| `max_pending` | `nil` | Backpressure limit (positive `Integer`); `nil` = unbounded |
| `stats` | `nil` | Optional `Stats` instance for counters |
| `throttle` | `0.0` | Capacity ratio where backoff begins; `0` or `nil` = off, else strictly between 0 and 1 |

**Raises:** `ArgumentError` if `type` is not `nil`, a `Class`, or a `Module`; if `max_pending` is not `nil` or a positive `Integer`; if `throttle` is out of range; or if `throttle` is set without `max_pending`.

```ruby
channel = TypedBus::Channel.new(:orders,
  type: Order,
  timeout: 10,
  max_pending: 100,
  throttle: 0.5
)
```

!!! note
    When using channels via `MessageBus`, these values are resolved through the configuration cascade. You don't normally construct channels directly with all parameters.

## Attributes

### `name` → `Symbol`

Channel name.

### `type` → `Class`, `nil`

Type constraint, or `nil` for untyped channels.

### `dead_letter_queue` → `DeadLetterQueue`

The channel's dead letter queue.

## Pub/Sub

### `publish(message)` → `DeliveryTracker`, `nil`

Publish a message to all current subscribers.

- Blocks the calling fiber if bounded and at capacity
- Applies throttle delay if configured
- Returns `nil` if no subscribers (message goes to DLQ)

**Raises:** `ArgumentError` for type mismatches. `RuntimeError` if closed.

### `subscribe(&block)` → `Integer`

Subscribe to messages. Returns the subscriber ID.

**Raises:** `ArgumentError` if no block is given. `RuntimeError` if closed.

### `unsubscribe(id_or_block)`

Remove a subscriber by integer ID or block reference.

## Query

### `subscriber_count` → `Integer`

Number of active subscribers.

### `pending_count` → `Integer`

Number of unresolved delivery trackers.

### `pending?` → `Boolean`

True when there are unresolved deliveries.

### `closed?` → `Boolean`

True if the channel has been closed.

## Lifecycle

### `close`

Stop accepting new publishes and subscribes. Pending deliveries are force-NACKed and routed to the DLQ.

### `clear!`

Hard reset: cancel all timeout tasks, discard pending state, clear DLQ. Does not mark the channel as closed.
