# Stats

`TypedBus::Stats`

Simple counter map for message bus activity. Fiber-safe — no mutex needed within a single Async reactor.

## Constructor

### `Stats.new`

Creates a new Stats instance with no counters.

## Methods

### `increment(key)` → `Integer`

Increment a named counter. Returns the new value.

```ruby
stats.increment(:orders_published)  # => 1
stats.increment(:orders_published)  # => 2
```

### `[](key)` → `Integer`

Read a counter value. Returns `0` for unknown keys.

```ruby
stats[:orders_published]  # => 2
stats[:nonexistent]       # => 0
```

### `reset!`

Zero all counters. Keys are preserved, values set to `0`.

### `to_h` → `Hash<Symbol, Integer>`

Return a snapshot (dup) of all counters.

```ruby
stats.to_h
# => { orders_published: 2, orders_delivered: 1 }
```

## Attributes

### `data` → `Hash`

Direct access to the underlying counter hash. Prefer `[]` and `to_h` for read access.
