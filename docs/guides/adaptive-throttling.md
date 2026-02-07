# Adaptive Throttling

When a bounded channel approaches capacity, adaptive throttling progressively slows publishers before they hit the hard backpressure block.

## Enabling Throttling

Throttling requires `max_pending` to be set:

```ruby
channel = TypedBus::Channel.new(:pipeline,
  max_pending: 10,
  throttle: 0.5,   # begin backoff at 50% remaining capacity
  timeout: 5
)
```

The `throttle` value is a `Float` between `0.0` (exclusive) and `1.0` (exclusive), representing the remaining-capacity ratio at which backoff begins.

## Backoff Curve

Below the threshold, each publish sleeps for `1 / (max_pending * remaining_ratio)` seconds — an asymptotic delay that approaches infinity as remaining capacity approaches zero.

With `max_pending: 10, throttle: 0.5`:

```
Publish  Pending  Remaining  Ratio  Delay
───────────────────────────────────────────
  1        0        10       1.0    —
  2        1         9       0.9    —
  3        2         8       0.8    —
  4        3         7       0.7    —
  5        4         6       0.6    —
  6        5         5       0.5    0.200s
  7        6         4       0.4    0.250s
  8        7         3       0.3    0.333s
  9        8         2       0.2    0.500s
 10        9         1       0.1    1.000s
 11       10         0       0.0    hard block
```

The first 50% of capacity fills at full speed. The last 50% applies increasing delays.

## Threshold Selection

Higher values begin backoff earlier (more conservative):

```ruby
TypedBus::Channel.new(:conservative, max_pending: 100, throttle: 0.8)  # backoff at 80%
TypedBus::Channel.new(:aggressive,   max_pending: 100, throttle: 0.3)  # backoff at 30%
```

## Bus-Level Default

Set a default throttle for all channels on a bus:

```ruby
bus = TypedBus::MessageBus.new(throttle: 0.5)

bus.add_channel(:orders, max_pending: 100)               # inherits 0.5
bus.add_channel(:alerts, max_pending: 20, throttle: 0.3) # overrides to 0.3
bus.add_channel(:logs,   max_pending: 50, throttle: 0.0) # disables throttle
```

## Validation

- `throttle` must be between `0.0` and `1.0` (exclusive)
- `throttle` requires `max_pending` to be set (raises `ArgumentError` otherwise)
- `throttle: 0.0` disables throttling (the default)

## Stats

Each throttled publish increments the `:throttled` stat:

```ruby
bus.stats[:orders_throttled]
```
