# API Reference

Complete method reference for every TypedBus class.

## Module

- [`TypedBus`](#typedbus-module) — top-level configuration and logger access

## Classes

- [Configuration](configuration.md) — global defaults and cascade resolution
- [MessageBus](message-bus.md) — registry facade for named channels
- [Channel](channel.md) — named pub/sub topic with acknowledgment tracking
- [Delivery](delivery.md) — per-subscriber message envelope
- [DeliveryTracker](delivery-tracker.md) — aggregates subscriber responses per publish
- [DeadLetterQueue](dead-letter-queue.md) — collects failed deliveries
- [Stats](stats.md) — per-channel counter map

---

## TypedBus Module

### `TypedBus.configuration`

Returns the global `Configuration` instance.

### `TypedBus.configuration=(config)`

Replaces the global `Configuration` instance.

### `TypedBus.configure { |config| ... }`

Yields the global `Configuration` for block-style setup.

### `TypedBus.reset_configuration!`

Restores factory defaults.

### `TypedBus.logger`

Shortcut for `TypedBus.configuration.logger`.

### `TypedBus.logger=(log)`

Shortcut for `TypedBus.configuration.logger = log`.
