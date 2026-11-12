## [Unreleased]

### Fixed

- `Channel#subscribe` and `MessageBus#subscribe` now raise `ArgumentError`
  when called without a block. Previously a blockless subscriber was
  registered with a nil handler, so every published message waited on an
  acknowledgment that could never arrive, and a bounded channel blocked
  publishers forever (#16). Found and fixed by BomberBot.
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
- The packaged gem now contains only the git-tracked `lib/**/*.rb` files,
  `README.md`, and `CHANGELOG.md` (plus a `LICENSE*` file once one is
  added). It previously shipped the docs site (including a 16.6 MB GIF and
  a 2.7 MB MP4), examples, CI workflows, and local dotfiles, making the
  `.gem` about 19.9 MB instead of 15 KB (#3). Found and fixed by BomberBot.
- Unsubscribing a subscriber while a publish is fanning out no longer leaves
  that message's delivery tracker pending forever (and, on a bounded channel,
  holding a `max_pending` slot). `Channel#publish` now snapshots subscriber
  ids and handlers together, so a subscriber removed mid-publish still
  receives that one message (#4).
- `max_pending` must be `nil` or a positive `Integer`. `Channel.new`,
  `MessageBus.new`, `MessageBus#add_channel`, and
  `Configuration#max_pending=` raise `ArgumentError` for `0`, negative, or
  non-Integer values instead of hanging or crashing on a later publish (#5).
- Logging examples 11-14 now print their DEBUG output (#17), and
  `examples/15_performance.rb` no longer requires the unused `csv` gem (#19).

### Changed

- `ratatui_ruby` and `aigcm` moved to an optional `:extras` bundle group;
  the default bundle no longer builds a Rust native extension.
- Refreshed `Gemfile.lock` to async 2.46.0 (#14).
- Removed the no-op `Configuration#initialize_copy` override (#21).
- Renamed gem from `async_typed_bus` to `typed_bus` (module `TypedBus`).

### Added

- MIT `LICENSE` file (#11); `documentation_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required` gemspec metadata (#12).
- CI workflow running the test suite on Ruby 3.2-4.0 plus a load smoke test
  outside the dev bundle (#20); Dependabot configuration (#15).
- Adaptive rate limiting via `throttle: Float` on Channel and MessageBus.
  The value (0.0 to 1.0) sets the remaining-capacity ratio where asymptotic
  backoff begins. Below that threshold, each publish sleeps for
  `1 / (max_pending * remaining_ratio)` seconds. No external dependencies.
- `MessageBus.new(throttle: 0.5)` sets a bus-wide default applied to every
  `add_channel` call. Per-channel override or `throttle: 0.0` to disable.
- `:throttled` stat counter recorded each time a publish is rate-limited.

## [0.1.0] - 2026-02-06

- Initial release
