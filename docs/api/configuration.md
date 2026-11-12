# Configuration

`TypedBus::Configuration`

Holds configurable defaults for the message bus system. Supports three-tier cascade: Global → Bus → Channel.

## Attributes

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `timeout` | `Numeric` | `30` | Delivery ACK deadline in seconds; `nil` = never auto-nack |
| `max_pending` | `Integer`, `nil` | `nil` | Backpressure limit (positive `Integer`); `nil` = unbounded |
| `throttle` | `Float` | `0.0` | Remaining-capacity ratio where backoff begins |
| `logger` | `Logger`, `nil` | `nil` | Ruby Logger instance |
| `log_level` | `Integer` | `Logger::INFO` | Log level applied to the logger |

## Constructor

### `Configuration.new`

Creates a new Configuration with factory defaults.

## Methods

### `timeout=(seconds)`

Sets the delivery ACK deadline. `nil` means deliveries never auto-nack.

### `max_pending=(limit)`

Sets the backpressure limit: `nil` (unbounded) or a positive `Integer`.

**Raises:** `ArgumentError` for anything else, such as `0`, `-1`, or `2.5`.

```ruby
config.max_pending = 0
# => ArgumentError: max_pending must be nil or a positive Integer, got 0
```

### `throttle=(ratio)`

Sets the throttle threshold: `nil` or `0` (off), or a number strictly between `0` and `1`.

**Raises:** `ArgumentError` for anything else, such as `1.5`, `-3`, or `"fast"`.

```ruby
config.throttle = 1.5
# => ArgumentError: throttle must be 0 (off) or between 0.0 and 1.0 (exclusive), got 1.5
```

A throttle also needs a `max_pending`. That is checked when a channel is created, because the two can be set in either order.

### `logger=(log)`

Sets the logger and applies the current `log_level` to it.

```ruby
config.logger = Logger.new($stdout)
# config.logger.level is now config.log_level
```

### `log_level=(level)`

Sets the log level and applies it to the current logger (if present).

```ruby
config.log_level = Logger::DEBUG
# config.logger.level is now Logger::DEBUG (if logger is set)
```

### `resolve(timeout:, max_pending:, throttle:)`

Merges overrides on top of this configuration's values. Parameters set to `:use_default` inherit from this config.

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | `:use_default` | Delivery ACK deadline |
| `max_pending` | `:use_default` | Backpressure limit |
| `throttle` | `:use_default` | Capacity ratio for adaptive backoff |

**Returns:** `Hash` with resolved `:timeout`, `:max_pending`, and `:throttle` values.

```ruby
config = TypedBus::Configuration.new
config.timeout = 60

config.resolve(timeout: 10)
# => { timeout: 10, max_pending: nil, throttle: 0.0 }

config.resolve
# => { timeout: 60, max_pending: nil, throttle: 0.0 }
```

### `dup`

Returns an independent shallow copy. The logger is intentionally shared (same Logger instance); all other fields are independent.

## Constants

### `DEFAULTS`

Frozen hash of factory defaults:

```ruby
{
  timeout: 30,
  max_pending: nil,
  throttle: 0.0,
  logger: nil,
  log_level: Logger::INFO
}
```
