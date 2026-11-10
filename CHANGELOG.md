## [Unreleased]

### Fixed

- `DeadLetterQueue#drain` no longer loses entries when the block raises
  partway through. Entries are now removed only after they are successfully
  yielded, so a raising block leaves the remaining entries in the queue for
  a later retry (#6). Found and fixed by BomberBot.
- Declare `logger` as a runtime dependency in the gemspec so
  `require "typed_bus"` loads under Bundler on Ruby 4.0+, where `logger`
  is a bundled gem rather than a default gem. Found and fixed by BomberBot.
- A throttled, bounded channel no longer hangs forever when published to at
  full capacity. Previously the adaptive backoff computed an infinite delay
  (`1 / 0`) and slept indefinitely; the throttle now yields at full capacity
  and lets backpressure block the publisher instead. Found and fixed by
  BomberBot.

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
