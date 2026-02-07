# Configuration

TypedBus resolves parameters through a three-tier cascade: **Global → Bus → Channel**. Each tier inherits from the one above unless explicitly overridden.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | `30` | Delivery ACK deadline in seconds |
| `max_pending` | `nil` | Backpressure limit; `nil` = unbounded |
| `throttle` | `0.0` | Remaining-capacity ratio where backoff begins; `0.0` = disabled |
| `logger` | `nil` | Ruby Logger instance (global-only) |
| `log_level` | `Logger::INFO` | Log level applied to the logger (global-only) |

## Global Defaults

Set defaults that apply to every bus and channel:

```ruby
TypedBus.configure do |config|
  config.timeout     = 60
  config.max_pending = 500
  config.throttle    = 0.5
  config.logger      = Logger.new($stdout)
  config.log_level   = Logger::DEBUG
end
```

## Bus-Level Overrides

Pass parameters to `MessageBus.new` to override globals for this bus:

```ruby
# Inherits global max_pending and throttle, overrides timeout
bus = TypedBus::MessageBus.new(timeout: 10)
```

Each bus gets an independent config snapshot. Mutating one does not affect the global or other buses.

## Channel-Level Overrides

Pass parameters to `add_channel` to override the bus defaults for this channel:

```ruby
# Inherits bus timeout, overrides max_pending
bus.add_channel(:alerts, max_pending: 50)
```

## Cascade Example

```ruby
TypedBus.configure do |config|
  config.timeout     = 60    # global default
  config.max_pending = 500
end

bus = TypedBus::MessageBus.new(timeout: 30)  # bus overrides timeout

bus.add_channel(:orders)              # timeout=30, max_pending=500
bus.add_channel(:alerts, timeout: 5)  # timeout=5,  max_pending=500
```

## Logger Shortcuts

```ruby
# These are equivalent:
TypedBus.configure { |c| c.logger = Logger.new($stdout) }
TypedBus.logger = Logger.new($stdout)

# Reading:
TypedBus.logger  # => the Logger instance
```

Setting `log_level` automatically applies it to the current logger. Setting a logger automatically applies the current `log_level` to it.

## Reset

Restore factory defaults (useful in tests):

```ruby
TypedBus.reset_configuration!
```

## Further Reading

- [Configuration Cascade](../architecture/configuration-cascade.md) — architecture details
- [API Reference: Configuration](../api/configuration.md) — full method reference
