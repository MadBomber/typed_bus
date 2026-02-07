# Configuration Cascade

TypedBus resolves configurable parameters through three tiers:

```
Global  →  Bus  →  Channel
```

Each tier inherits from the one above unless explicitly overridden.

## How It Works

```mermaid
flowchart LR
    G[Global Config] -->|dup| B[Bus Config]
    B -->|resolve| C[Channel Values]
```

1. **Global** — `TypedBus.configure { |c| ... }` sets defaults for all buses. Stored as a singleton `Configuration` instance.
2. **Bus** — `MessageBus.new(timeout: 10)` creates a `dup` of the global config, then applies any explicit overrides. Each bus holds its own independent `Configuration`.
3. **Channel** — `bus.add_channel(:name, timeout: 5)` resolves values via the bus's config. The channel receives fully resolved scalars — it has no awareness of the cascade.

## The `:use_default` Sentinel

The sentinel value `:use_default` means "inherit from the tier above." It is the default for all cascade parameters at both bus and channel levels.

This sentinel is necessary to distinguish "not provided" from an explicit `nil`. For `max_pending`, `nil` means "unbounded" — a meaningful value that must be distinguishable from "use whatever the parent says."

```ruby
# These are different:
bus.add_channel(:a)                    # max_pending inherited from bus
bus.add_channel(:b, max_pending: nil)  # max_pending explicitly unbounded
```

## Cascaded Parameters

| Parameter | Default | Cascades? |
|-----------|---------|-----------|
| `timeout` | `30` | Global → Bus → Channel |
| `max_pending` | `nil` | Global → Bus → Channel |
| `throttle` | `0.0` | Global → Bus → Channel |
| `logger` | `nil` | Global only |
| `log_level` | `Logger::INFO` | Global only |

`logger` and `log_level` are global-only because the logger is a shared resource. All buses and channels read the logger via `TypedBus.logger`.

## Isolation

Each bus gets an independent config snapshot via `dup`. Changing a bus's config does not affect the global or other buses:

```ruby
TypedBus.configure { |c| c.timeout = 60 }

bus_a = TypedBus::MessageBus.new(timeout: 10)
bus_b = TypedBus::MessageBus.new(timeout: 99)

bus_a.config.timeout  # => 10
bus_b.config.timeout  # => 99
TypedBus.configuration.timeout  # => 60 (unchanged)
```

## Implementation

The cascade logic lives in `Configuration#resolve`:

```ruby
def resolve(timeout: :use_default, max_pending: :use_default, throttle: :use_default)
  {
    timeout:     timeout     == :use_default ? @timeout     : timeout,
    max_pending: max_pending == :use_default ? @max_pending : max_pending,
    throttle:    throttle    == :use_default ? @throttle    : throttle
  }
end
```

`MessageBus#initialize` calls `resolve` on the global config. `MessageBus#add_channel` calls `resolve` on the bus config. The channel receives the final resolved values.
