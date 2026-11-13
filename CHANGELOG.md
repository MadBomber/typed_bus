## [Unreleased]

### Fixed

- `Channel#subscribe` and `MessageBus#subscribe` now raise `ArgumentError`
  when called without a block. Previously a blockless subscriber was
  registered with a nil handler, so every published message waited on an
  acknowledgment that could never arrive, and a bounded channel blocked
  publishers forever (#16). Found and fixed by BomberBot.
- `DeadLetterQueue#drain` with a block no longer loses entries when the
  block raises, and no longer loops when the block re-queues entries. It
  empties the queue first and yields that snapshot once; entries added
  during the drain (such as a retry that fails again) wait for the next
  drain. If the block raises, the entry it was handling and the ones not
  yet yielded go back to the front of the queue (#6). Found and fixed by
  BomberBot.
- Declare `logger` as a runtime dependency in the gemspec so
  `require "typed_bus"` loads under Bundler on Ruby 4.0+, where `logger`
  is a bundled gem rather than a default gem. Found and fixed by BomberBot.
- A throttled, bounded channel no longer hangs forever when published to at
  full capacity. Previously the adaptive backoff computed an infinite delay
  (`1 / 0`) and slept indefinitely; the throttle now yields at full capacity
  and lets backpressure block the publisher instead. Found and fixed by
  BomberBot.
- The packaged gem now contains only the git-tracked `lib/**/*.rb` files,
  `README.md`, `CHANGELOG.md`, and `LICENSE`. It previously shipped the
  docs site (including a 16.6 MB GIF and a 2.7 MB MP4), examples, CI
  workflows, and local dotfiles, making the `.gem` about 19.9 MB instead
  of 15 KB (#3). Found and fixed by BomberBot.
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
- `Channel#publish` now raises the closed-channel error when the channel is
  closed while the publisher is sleeping in the throttle or blocked on
  backpressure. Previously that publish still delivered into the closed
  channel and left a delivery pending until its timeout.
- A raising `on_dead_letter` callback no longer drops the `nacked`/`timed_out`
  and `dead_lettered` stats for that delivery. The channel now records them
  before it pushes to the dead letter queue (#36).
- The DEBUG "backpressure: waiting for capacity" and "capacity available"
  lines are logged only when a publisher actually waits, not on every
  publish to a bounded channel (#31).
- `timeout: nil` now logs as `timeout=none` instead of `timeout=s`, and the
  option tables document that `nil` means never auto-nack (#27).
- `MessageBus#add_channel` logs `added channel :name` after the channel is
  built, instead of `adding channel :name` before validation, so a rejected
  `add_channel` no longer logs as if the channel had been added (#47).

### Changed

- The `MessageBus` "Unknown channel" `ArgumentError` now shows the name with
  `inspect` and lists the registered channels, e.g.
  `Unknown channel: "orders" (registered: :orders, :payments)`, so a
  String/Symbol mix-up is visible. Found and fixed by BomberBot.
- A channel's `type:` must be `nil`, a `Class`, or a `Module`. `Channel.new`
  and `MessageBus#add_channel` raise `ArgumentError` for anything else;
  previously the channel was created and every publish raised a bare
  `TypeError` (#34).
- `throttle` must be `nil`, `0`, or a number strictly between 0 and 1.
  `Configuration#throttle=`, `MessageBus.new`, `MessageBus#add_channel`, and
  `Channel.new` raise `ArgumentError` for anything else as soon as it is set.
  Previously an out-of-range bus or global throttle failed only when a
  channel was added, and a non-numeric one silently turned throttling
  off (#33).
- `ratatui_ruby` and `aigcm` moved to an optional `:extras` bundle group;
  the default bundle no longer builds a Rust native extension.
- Refreshed `Gemfile.lock` to async 2.46.0 (#14).
- Removed the no-op `Configuration#initialize_copy` override (#21).

### Added

- MIT `LICENSE` file (#11); `documentation_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required` gemspec metadata (#12).
- CI workflow running the test suite on Ruby 3.2-4.0 plus a load smoke test
  outside the dev bundle (#20); Dependabot configuration (#15).

## [0.0.1] - 2026-02-07

- Initial release

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
