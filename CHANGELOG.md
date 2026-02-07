## [Unreleased]

### Changed

- Renamed gem from `async_typed_bus` to `typed_bus` (module `TypedBus`).

### Added

- Adaptive rate limiting via `throttle: Float` on Channel and MessageBus.
  The value (0.0 to 1.0) sets the remaining-capacity ratio where asymptotic
  backoff begins. Below that threshold, each publish sleeps for
  `1 / (max_pending * remaining_ratio)` seconds. No external dependencies.
- `MessageBus.new(throttle: 0.5)` sets a bus-wide default applied to every
  `add_channel` call. Per-channel override or `throttle: 0.0` to disable.
- `:throttled` stat counter recorded each time a publish is rate-limited.

## [0.1.0] - 2026-02-06

- Initial release
