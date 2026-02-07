# Examples

TypedBus ships with runnable examples in the `examples/` directory. Run any example from the project root:

```bash
bundle exec ruby examples/01_basic_usage.rb
```

## Demo Index

| # | File | Description |
|---|------|-------------|
| 00 | `00_config.rb` | Three-tier configuration cascade. Global defaults, bus-level overrides, per-channel overrides, inheritance, and `reset_configuration!`. |
| 01 | `01_basic_usage.rb` | Basic pub/sub with explicit acknowledgment. One channel, one subscriber, `ack!` after each message. |
| 02 | `02_typed_channels.rb` | Type-constrained channels. Publishing the wrong type raises `ArgumentError` at the publish site. |
| 03 | `03_multiple_subscribers.rb` | Fan-out delivery. Every subscriber gets its own `Delivery`; a message is only "delivered" when all subscribers ACK. Shows `DeliveryTracker` state queries. |
| 04 | `04_nack_and_dead_letters.rb` | Explicit rejection with `nack!`. Rejected deliveries route to the dead letter queue. Shows DLQ iteration and `drain` for retry. |
| 05 | `05_delivery_timeout.rb` | Delivery deadlines. Subscribers that don't respond within the timeout are auto-NACKed. Shows `timed_out?` flag. |
| 06 | `06_backpressure.rb` | Bounded channels with `max_pending`. The publisher fiber blocks when the limit is reached and resumes as subscribers ACK. |
| 07 | `07_message_bus.rb` | `MessageBus` registry facade. Manages multiple typed channels, aggregates stats, single entry point for publish/subscribe. |
| 08 | `08_error_handling.rb` | Edge cases: subscriber exceptions (auto-nack), no subscribers (DLQ), unsubscribe mid-stream, close force-nacks, publishing to closed channel. |
| 09 | `09_stats_and_monitoring.rb` | Per-channel stat counters. Combines DLQ callbacks with stats for real-time alerting. Shows `reset!`. |
| 10 | `10_concurrent_pipeline.rb` | Multi-stage event pipeline: ingest, validate, process. Typed messages, backpressure, timeouts, DLQ monitoring, graceful shutdown. |
| 11 | `11_logging_basic.rb` | Structured logging via `TypedBus.logger`. Lifecycle log output for channel creation, subscriber registration, publish, delivery, ack, tracker resolution. |
| 12 | `12_logging_failures.rb` | Failure-path logging: explicit nacks, delivery timeouts, no-subscriber dead-lettering, DLQ drain. Colorized output. |
| 13 | `13_logging_backpressure.rb` | Backpressure logging. DEBUG-level messages as the publisher fiber blocks and resumes while a slow subscriber drains a bounded channel. |
| 14 | `14_adaptive_throttling.rb` | Adaptive rate limiting with `throttle: Float`. Asymptotic backoff as a bounded channel fills, bus-level throttle defaults with per-channel overrides. |

## Running All Examples

```bash
for f in examples/*.rb; do
  echo "=== $f ==="
  bundle exec ruby "$f"
  echo
done
```
