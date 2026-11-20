# Graceful Shutdown

TypedBus provides several levels of cleanup for stopping channels and buses.

## Close a Channel

Stops accepting new publishes and subscribes. Pending deliveries are force-NACKed and routed to the DLQ.

```ruby
channel.close
channel.closed?  # => true
```

After closing:

- `publish` raises `RuntimeError`, including for publishers that were already
  waiting on `max_pending` or throttle when `close` ran: they wake up and raise
  `Channel :name is closed` instead of delivering
- `subscribe` raises `RuntimeError`
- The DLQ retains its entries for inspection

If an `on_dead_letter` callback raises during the force-nack, every pending delivery is still nacked and the first error is re-raised once they are all handled. Call `close` inside a `begin`/`rescue` if your callback can fail.

## Close All Channels

```ruby
bus.close_all
```

Closes every channel on the bus. Each channel's pending deliveries are force-NACKed. If closing one channel raises, the others are still closed and the first error is re-raised afterwards.

## Clear a Channel

Hard reset: cancels all timeout tasks, discards pending deliveries, and clears the DLQ.

```ruby
channel.clear!
```

Unlike `close`, `clear!` does not mark the channel as closed — you can continue using it.

## Clear a Bus

Clears all channels and resets stats:

```ruby
bus.clear!
```

## Remove a Channel

Close and remove a channel from the bus registry:

```ruby
bus.remove_channel(:orders)
bus.channel?(:orders)  # => false
```

Removing a nonexistent channel is a no-op.

## Shutdown Order

For a clean shutdown:

1. Stop publishing new messages
2. Wait for pending deliveries to resolve (or let timeouts fire)
3. Process any DLQ entries
4. Call `bus.close_all`

```ruby
Async do
  # ... normal operations ...

  # Shutdown
  sleep(timeout_duration)  # let pending deliveries settle
  bus.dead_letters(:orders).drain { |d| reprocess(d.message) }
  bus.close_all
end
```
