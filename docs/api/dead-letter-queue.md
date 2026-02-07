# DeadLetterQueue

`TypedBus::DeadLetterQueue`

Stores deliveries that failed — either explicitly NACKed or timed out. Each Channel owns a DLQ. Includes `Enumerable`.

## Constructor

### `DeadLetterQueue.new(&on_dead_letter)`

Optionally accepts a block that fires on each `push`.

## Methods

### `push(delivery)`

Add a failed delivery.

### `size` → `Integer`

Number of entries.

### `empty?` → `Boolean`

True if no entries.

### `each(&block)`

Iterate over dead letters without removing them.

### `drain { |delivery| ... }` → `Array<Delivery>`

Yield each dead letter and remove it from the queue. Returns the drained entries. Without a block, just removes and returns them.

### `clear!`

Discard all entries.

### `on_dead_letter { |delivery| ... }`

Register or replace the callback fired when entries arrive.

## Enumerable

`DeadLetterQueue` includes `Enumerable`, so you can use `map`, `select`, `count`, `any?`, etc.:

```ruby
dlq = channel.dead_letter_queue

timed_out = dlq.count(&:timed_out?)
messages  = dlq.map(&:message)
```
