# Delivery

`TypedBus::Delivery`

Envelope wrapping a message delivered to a single subscriber. Each subscriber receives its own Delivery instance for the same message.

## Constructor

### `Delivery.new(message, channel_name:, subscriber_id:, timeout:, on_ack:, on_nack:)`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `message` | required | The published payload |
| `channel_name` | required | Originating channel name |
| `subscriber_id` | required | Target subscriber's ID |
| `timeout` | `nil` | Seconds before auto-nack; `nil` = no timeout |
| `on_ack` | `nil` | Callback proc called with subscriber_id on ack |
| `on_nack` | `nil` | Callback proc called with subscriber_id on nack |

!!! note
    Deliveries are created internally by `Channel#publish`. You don't normally construct them directly.

## Attributes

### `message` → `Object`

The published payload.

### `channel_name` → `Symbol`

The originating channel.

### `subscriber_id` → `Integer`

The target subscriber's ID.

## Resolution

### `ack!`

Mark as successfully processed. Cancels the timeout timer.

**Raises:** `RuntimeError` if already resolved.

### `nack!`

Mark as failed. Routes to the dead letter queue. Cancels the timeout timer.

**Raises:** `RuntimeError` if already resolved.

## State

### `pending?` → `Boolean`

Not yet resolved.

### `acked?` → `Boolean`

Successfully acknowledged.

### `nacked?` → `Boolean`

Explicitly rejected or timed out.

### `timed_out?` → `Boolean`

True if the nack was caused by timeout (as opposed to explicit `nack!`).

## Timeout

### `cancel_timeout`

Cancel the timeout timer without resolving the delivery. Used internally during `close` and `clear!`.
