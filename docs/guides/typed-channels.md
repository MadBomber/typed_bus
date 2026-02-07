# Typed Channels

Channels can enforce a type constraint on published messages. When set, every message must pass an `is_a?` check against the specified class.

## Setting a Type

```ruby
channel = TypedBus::Channel.new(:orders, type: Order, timeout: 5)
```

Or via MessageBus:

```ruby
bus.add_channel(:orders, type: Order)
```

## Type Enforcement

```ruby
Async do
  channel.publish(Order.new)    # OK
  channel.publish("not valid")  # raises ArgumentError
end
```

The error message includes both the expected and actual types:

```
Expected Order, got String on channel :orders (ArgumentError)
```

## Subclasses

The check uses `is_a?`, so subclasses pass:

```ruby
class PriorityOrder < Order; end

channel = TypedBus::Channel.new(:orders, type: Order, timeout: 5)

Async do
  channel.publish(PriorityOrder.new)  # OK — PriorityOrder is_a? Order
end
```

## Untyped Channels

Omit `type:` (or pass `nil`) to accept any message:

```ruby
bus.add_channel(:events)  # accepts anything
```

## When to Use Types

Type constraints are useful when:

- Multiple publishers share a channel and you want compile-time-like safety
- Messages carry structured data (Structs, Data classes) and you want to catch serialization mistakes early
- You want to document the channel's contract in code

!!! note
    The `type:` parameter is per-channel only. It is not part of the configuration cascade — there is no meaningful "default type."
