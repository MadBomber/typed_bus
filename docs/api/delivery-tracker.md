# DeliveryTracker

`TypedBus::DeliveryTracker`

Tracks the delivery state of a single published message across N subscribers. Created per `publish` call.

## Constructor

### `DeliveryTracker.new(message, channel_name:, subscriber_ids:)`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `message` | required | The published payload |
| `channel_name` | required | Originating channel name |
| `subscriber_ids` | required | `Array<Integer>` of subscriber IDs |

!!! note
    Trackers are created internally by `Channel#publish`. You don't normally construct them directly.

## Attributes

### `message` → `Object`

The published payload.

### `channel_name` → `Symbol`

The originating channel.

## Recording Responses

### `ack(subscriber_id)`

Record an ACK from a subscriber. Checks for resolution after recording.

### `nack(subscriber_id)`

Record a NACK from a subscriber. Fires the `on_dead_letter` callback. Checks for resolution after recording.

## State

### `fully_delivered?` → `Boolean`

True when every subscriber has ACKed.

### `fully_resolved?` → `Boolean`

True when all subscribers have responded (acked or nacked).

### `pending_count` → `Integer`

Number of subscribers still pending.

## Callbacks

### `on_complete { ... }`

Called when all subscribers have resolved and every one ACKed (successful delivery).

### `on_resolved { ... }`

Called when all subscribers have resolved, regardless of outcome. Used for cleanup (e.g., removing from pending map, signaling backpressure).

### `on_dead_letter { |subscriber_id| ... }`

Called for each NACK, receiving the subscriber ID.
