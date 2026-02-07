# Examples

Run any example from the project root:

```bash
ruby -Ilib examples/01_basic_usage.rb
```

## Demos

| # | File | Description |
|---|------|-------------|
| 00 | `00_config.rb` | Three-tier configuration cascade. Shows `TypedBus.configure` for global defaults, bus-level overrides, and per-channel overrides with inheritance and `reset_configuration!`. |
| 01 | `01_basic_usage.rb` | Basic pub/sub with explicit acknowledgment. One channel, one subscriber, `ack!` after each message. |
| 02 | `02_typed_channels.rb` | Type-constrained channels. Publishing the wrong type raises `ArgumentError` at the publish site. |
| 03 | `03_multiple_subscribers.rb` | Fan-out delivery. Every subscriber gets its own `Delivery`; a message is only "delivered" when all subscribers ack. Shows `DeliveryTracker` state queries. |
| 04 | `04_nack_and_dead_letters.rb` | Explicit rejection with `nack!`. Rejected deliveries route to the dead letter queue. Shows DLQ iteration and `drain` for retry. |
| 05 | `05_delivery_timeout.rb` | Delivery deadlines. Subscribers that don't respond within the timeout are auto-nacked. Shows `timed_out?` flag to distinguish timeouts from explicit nacks. |
| 06 | `06_backpressure.rb` | Bounded channels with `max_pending`. The publisher fiber blocks when the limit is reached and resumes as subscribers ack. |
| 07 | `07_message_bus.rb` | `MessageBus` registry facade. Manages multiple typed channels, aggregates stats, and provides a single entry point for publish/subscribe. |
| 08 | `08_error_handling.rb` | Edge case handling: subscriber exceptions (auto-nack), publishing with no subscribers (DLQ), unsubscribe mid-stream, close force-nacks pending deliveries, and publishing to a closed channel. |
| 09 | `09_stats_and_monitoring.rb` | Per-channel stat counters (published, delivered, nacked, timed_out, dead_lettered). Combines DLQ callbacks with stats for real-time alerting. Shows `reset!`. |
| 10 | `10_concurrent_pipeline.rb` | Multi-stage event pipeline: ingest, validate, process. Combines typed messages, backpressure, timeouts, DLQ monitoring, and graceful shutdown into a realistic scenario. |
| 11 | `11_logging_basic.rb` | Structured logging via `TypedBus.logger`. Shows lifecycle log output for channel creation, subscriber registration, publish, delivery, ack, and tracker resolution. |
| 12 | `12_logging_failures.rb` | Failure-path logging: explicit nacks, delivery timeouts, no-subscriber dead-lettering, and DLQ drain. Colorized output highlights warnings and errors. |
| 13 | `13_logging_backpressure.rb` | Backpressure logging. Shows DEBUG-level messages as the publisher fiber blocks and resumes while a slow subscriber drains a bounded channel. |
| 14 | `14_adaptive_throttling.rb` | Adaptive rate limiting with `throttle: Float`. Demonstrates asymptotic backoff as a bounded channel fills, plus bus-level throttle defaults with per-channel overrides. |
