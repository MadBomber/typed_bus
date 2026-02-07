# Concurrency Model

TypedBus uses **fiber-only concurrency** powered by the [async](https://github.com/socketry/async) gem. There are no mutexes and no threads anywhere in the library.

## Single Reactor

All TypedBus state lives within a single Async reactor. The `Async { }` block creates the reactor, and all publish/subscribe operations run as fibers within it.

```ruby
Async do
  bus.publish(:events, "hello")   # runs as a fiber
  bus.publish(:events, "world")   # runs as a fiber
end
```

## Why Fibers?

Ruby fibers provide cooperative concurrency:

- **No race conditions** — only one fiber runs at a time within a reactor
- **No locks needed** — shared state is safe without mutexes
- **Yielding, not blocking** — `sleep`, backpressure waits, and throttle delays yield the fiber, allowing other fibers to progress

## Where Async Tasks Are Created

TypedBus creates Async tasks in two places:

1. **Subscriber dispatch** — each subscriber's block runs in its own `Async` task when a message is published. This allows multiple subscribers to process concurrently.

2. **Delivery timeout** — each Delivery starts an `Async` task that sleeps for the timeout duration and then auto-nacks if the delivery is still pending.

## Implications

- `publish` must be called inside an `Async { }` block (or within an existing reactor)
- Subscriber blocks execute concurrently with each other
- A subscriber that never returns will keep its Delivery pending until the timeout fires
- Backpressure (`wait_for_capacity`) blocks the *publishing fiber* — other fibers continue running
- Throttle delays (`sleep`) yield the *publishing fiber* — other fibers continue running
