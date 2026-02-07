# Dead Letter Queues

Every channel has a dead letter queue (DLQ) that collects failed deliveries.

## What Goes to the DLQ

- Deliveries explicitly NACKed by subscribers
- Deliveries that time out (auto-nack)
- Messages published with no subscribers

## Accessing the DLQ

Via MessageBus:

```ruby
dlq = bus.dead_letters(:orders)
```

Via Channel directly:

```ruby
dlq = channel.dead_letter_queue
```

## Inspecting Entries

```ruby
dlq.size     # number of entries
dlq.empty?   # true if no entries

dlq.each do |delivery|
  puts "#{delivery.message} failed on subscriber ##{delivery.subscriber_id}"
  puts "  timed out? #{delivery.timed_out?}"
end
```

The DLQ includes `Enumerable`, so you can use `map`, `select`, `count`, etc.

## Draining for Retry

`drain` yields each entry and removes it from the queue:

```ruby
channel.dead_letter_queue.drain do |delivery|
  retry_message(delivery.message)
end
```

Without a block, `drain` returns the array of drained entries:

```ruby
entries = channel.dead_letter_queue.drain
entries.each { |d| reprocess(d.message) }
```

## Real-Time Callback

Register a callback that fires whenever a new entry arrives:

```ruby
channel.dead_letter_queue.on_dead_letter do |delivery|
  alert("Dead letter on :#{delivery.channel_name}: #{delivery.message}")
end
```

## Clearing

Discard all DLQ entries:

```ruby
channel.dead_letter_queue.clear!
```

Or clear the entire channel (including DLQ, pending deliveries, and timeout tasks):

```ruby
channel.clear!
```
