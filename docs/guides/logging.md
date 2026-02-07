# Logging

TypedBus produces structured log output from all components when a logger is configured.

## Enabling Logging

```ruby
TypedBus.configure do |config|
  config.logger    = Logger.new($stdout)
  config.log_level = Logger::INFO
end
```

Or use the shortcut:

```ruby
TypedBus.logger = Logger.new($stdout)
```

Set to `nil` (the default) to disable logging.

## Log Level

Setting `log_level` automatically applies it to the logger:

```ruby
TypedBus.configure do |config|
  config.logger    = Logger.new($stdout)
  config.log_level = Logger::DEBUG     # applies to the logger
end

# Or change it later:
TypedBus.configuration.log_level = Logger::WARN
```

## What Gets Logged

### INFO Level

- Bus initialization
- Channel creation with parameters
- Subscriber registration and unsubscription
- Message publish events
- Delivery acks
- DLQ drains
- Channel close and clear operations

### WARN Level

- Delivery nacks
- Delivery timeouts
- DLQ entries added
- Publishing with no subscribers

### ERROR Level

- Subscriber exceptions
- Type mismatches

### DEBUG Level

- Individual subscriber notifications
- Throttle delay calculations
- Backpressure wait/resume events

## Log Format

All log messages are prefixed with the originating component:

```
TypedBus::MessageBus message bus initialized (default_throttle=off)
TypedBus::Channel[:orders] channel created (type=Order, timeout=10s, max_pending=100, throttle=off)
TypedBus::Channel[:orders] published message (type=Order, subscribers=2)
TypedBus::Delivery[:orders#1] acked
TypedBus::DeliveryTracker[:orders] fully delivered (all 2 subscribers acked)
```

## Custom Formatter

Use a custom formatter for colorized or structured output:

```ruby
logger = Logger.new($stdout)
logger.formatter = proc do |severity, datetime, _progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  "#{timestamp} [#{severity.ljust(5)}] #{msg}\n"
end

TypedBus.configure do |config|
  config.logger    = logger
  config.log_level = Logger::DEBUG
end
```
