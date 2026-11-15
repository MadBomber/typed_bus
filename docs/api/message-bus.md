# MessageBus

`TypedBus::MessageBus`

Registry facade for named, typed pub/sub channels with shared statistics.

## Constructor

### `MessageBus.new(timeout:, max_pending:, throttle:)`

Creates a new bus. All parameters default to `:use_default`, inheriting from the global configuration.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | `:use_default` | Delivery ACK deadline for channels in seconds; `nil` = never auto-nack |
| `max_pending` | `:use_default` | Backpressure limit for channels |
| `throttle` | `:use_default` | Throttle threshold for channels |

**Raises:** `ArgumentError` if `max_pending` is not `nil` or a positive `Integer`, or if `throttle` is not `nil`, `0`, or a number strictly between 0 and 1.

```ruby
bus = TypedBus::MessageBus.new(timeout: 10, throttle: 0.5)
```

## Attributes

### `stats` → `Stats`

The shared Stats instance for all channels on this bus.

### `config` → `Configuration`

The bus-level Configuration (independent copy of global config with overrides applied).

## Channel Management

### `add_channel(name, type:, timeout:, max_pending:, throttle:)` → `Channel`

Register a named channel. Parameters default to `:use_default`, inheriting from the bus config.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `name` | required | `Symbol` channel name |
| `type` | `nil` | Optional `Class` or `Module` constraint for messages |
| `timeout` | `:use_default` | Delivery ACK deadline in seconds; `nil` = never auto-nack |
| `max_pending` | `:use_default` | Backpressure limit |
| `throttle` | `:use_default` | Throttle threshold |

**Raises:** `ArgumentError` if `type` is not `nil`, a `Class`, or a `Module`; if `max_pending` or `throttle` is invalid; or if the effective `throttle` is on without a `max_pending`. A rejected channel is not registered.

### `remove_channel(name)`

Close and remove a channel. No-op for unknown channels.

### `channel?(name)` → `Boolean`

Check if a channel exists.

### `channel_names` → `Array<Symbol>`

List registered channel names.

## Pub/Sub

### `publish(channel_name, message)` → `DeliveryTracker`, `nil`

Publish a message to a named channel. Returns the `DeliveryTracker` or `nil` if no subscribers.

**Raises:** `ArgumentError` for unknown channels, type mismatches. `RuntimeError` for closed channels.

### `subscribe(channel_name, &block)` → `Integer`

Subscribe to a named channel. Returns the subscriber ID.

**Raises:** `ArgumentError` for unknown channels or when no block is given. `RuntimeError` for closed channels.

### `unsubscribe(channel_name, id_or_block)`

Remove a subscriber by ID or block reference.

## Query

### `pending?(channel_name)` → `Boolean`

Check if a channel has unresolved deliveries.

### `pending_count(channel_name)` → `Integer`

Number of unresolved deliveries.

### `dead_letters(channel_name)` → `DeadLetterQueue`

Access a channel's dead letter queue.

## Lifecycle

### `close(channel_name)`

Close a specific channel. Pending deliveries are force-NACKed.

### `close_all`

Close all channels.

### `clear!`

Close all channels, clear DLQs, and reset stats.
