# Concepts

TypedBus is built around a small set of core concepts. Understanding these makes the entire library predictable.

## Channels

A **channel** is a named pub/sub topic. Publishers send messages to a channel; subscribers receive them. Each channel can optionally enforce a type constraint on its messages.

Channels are the unit of configuration — each has its own timeout, backpressure limit, and throttle setting.

## Deliveries

When a message is published to a channel with subscribers, each subscriber receives a **Delivery** envelope wrapping the original message. The subscriber must explicitly resolve the delivery by calling `ack!` (success) or `nack!` (failure).

If neither is called before the channel's timeout expires, the delivery auto-nacks.

## Delivery Tracker

A **DeliveryTracker** aggregates the responses from all subscribers for a single published message. A message is considered "delivered" only when every subscriber has ACKed. If any subscriber NACKs, the failed deliveries route to the dead letter queue.

## Dead Letter Queue

Every channel has a **Dead Letter Queue** (DLQ) that collects failed deliveries. Entries arrive from:

- Explicit `nack!` calls
- Delivery timeouts (auto-nack)
- Messages published with no subscribers

The DLQ supports iteration, draining for retry, and callbacks for real-time alerting.

## MessageBus

The **MessageBus** is a registry facade that manages multiple named channels with shared statistics. It provides a single entry point for publish, subscribe, and lifecycle operations.

## Configuration Cascade

TypedBus resolves configurable parameters through three tiers:

```
Global  →  Bus  →  Channel
```

Each tier inherits from the one above unless explicitly overridden. See [Configuration Cascade](architecture/configuration-cascade.md) for details.

## Concurrency Model

TypedBus uses **fiber-only concurrency** powered by the `async` gem. There are no mutexes and no threads. All state is managed within a single Async reactor. Operations like backpressure waits and throttle sleeps yield the calling fiber, not the thread.
