# Publish Flow

When you call `channel.publish(message)`, the following steps execute in order:

```mermaid
flowchart TD
    A[publish called] --> B{Channel closed?}
    B -- yes --> ERR[raise RuntimeError]
    B -- no --> C[Type check]
    C --> D{Throttle enabled?}
    D -- yes --> E[Apply throttle delay]
    D -- no --> F{Bounded channel?}
    E --> F
    F -- yes --> G[Wait for capacity]
    F -- no --> CL{Closed while waiting?}
    G --> CL
    CL -- yes --> ERR
    CL -- no --> H{Subscribers?}
    H -- none --> I[Route to DLQ]
    H -- 1+ --> J[Create DeliveryTracker]
    J --> K[Fan out Delivery per subscriber]
    K --> L[Each subscriber runs in Async task]
    L --> M{ack! or nack!}
    M -- ack --> N[Tracker records ack]
    M -- nack --> O[Tracker records nack → DLQ]
    M -- timeout --> P[Auto-nack → DLQ]
    N --> Q{All resolved?}
    O --> Q
    P --> Q
    Q -- yes, all acked --> R[on_complete → delivered stat]
    R --> S[on_resolved → cleanup, free capacity]
    Q -- yes, some nacked --> S
```

## Step-by-Step

### 1. Guard: Closed Channel

If the channel is closed, `publish` raises `RuntimeError`. No message is delivered.

### 2. Type Check

If the channel has a `type:` constraint, the message's class is verified with `is_a?`. A mismatch raises `ArgumentError`.

### 3. Throttle

If `throttle` is configured and the channel is bounded, the remaining capacity ratio is checked. Below the threshold, the publisher sleeps for `1 / (max_pending * remaining_ratio)` seconds — an asymptotic delay that approaches infinity as remaining capacity approaches zero.

### 4. Backpressure

If the channel is bounded (`max_pending` is set) and the pending delivery count has reached the limit, the publishing fiber blocks on an `Async::Condition` until a delivery resolves and frees a slot. Any resolution counts: ack, nack, timeout, `close`, or `clear!`.

After the throttle and backpressure waits, the closed guard runs again. If the channel was closed while the publisher slept or waited, `publish` raises `RuntimeError` and the message is not delivered.

### 5. Fan-Out

A `DeliveryTracker` is created for this message, tracking the set of current subscriber IDs. Each subscriber receives its own `Delivery` envelope in a separate `Async` task.

### 6. Resolution

Each subscriber must call `ack!` or `nack!` on its Delivery. If neither is called before the timeout, the delivery auto-nacks. The tracker aggregates responses:

- **All acked** — the `on_complete` callback fires, incrementing the `:delivered` stat.
- **Any nacked** — NACKed deliveries are pushed to the dead letter queue.

In both cases the `on_resolved` callback then fires for cleanup: it runs once every subscriber has resolved, whatever the outcome.

### 7. Backpressure Release

When a tracker resolves, the pending delivery is removed and `@backpressure.signal` wakes any blocked publisher fiber. `close` and `clear!` also signal, so a waiting publisher re-checks capacity and the closed guard.

## No-Subscriber Path

If there are no subscribers when `publish` is called, the message is wrapped in a Delivery, immediately NACKed, and pushed to the dead letter queue. The `:nacked` and `:dead_lettered` stats are incremented.
