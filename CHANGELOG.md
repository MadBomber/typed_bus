## [Unreleased]

## [0.1.0] - 2026-11-19

First release since 0.0.1. In short:

- **Ruby 4.0 or newer is now required.** Ruby 3.2 and 3.3 are no longer
  supported.
- **Reliability fixes.** Publishers and deliveries no longer hang or stay
  pending forever when a channel closes, a subscriber unsubscribes, or an
  `on_dead_letter` callback raises; `DeadLetterQueue#drain` no longer loses
  or loops on entries; stats no longer miscount.
- **Stricter validation.** Invalid `type:`, `throttle:`, `max_pending:` and
  `log_level` values, and `subscribe` without a block, now raise
  `ArgumentError` up front instead of failing or hanging later.
- **A much smaller gem.** The package holds only the library and top-level
  docs: about 15 KB instead of 19.9 MB.
- **Project tooling.** CI, Dependabot, a LICENSE file, `llms.txt`, and
  quality gates run through asgard in place of Rake.

### Fixed

- `Channel#close` now nacks every pending delivery even when an
  `on_dead_letter` callback raises, and `MessageBus#close_all` closes every
  channel even when closing one raises. Both re-raise the first error once
  all the work is done. Previously the first error stopped the loop, so with
  `timeout: nil` the remaining deliveries stayed pending forever and later
  channels were left open (#75).
- `MessageBus#publish` no longer counts a message in `<channel>_published`
  when the channel is already closed or the message has the wrong type.
  Those publishes raise and were still counted, which inflated the counter
  and skewed rates computed from it.
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
  yet yielded go back to the front of the queue (#6). If the block exits
  early with `break` or `return`, the entry it was handling counts as done
  and the ones not yet yielded go back on the queue; in 0.0.1 they were
  lost (#29). Found and fixed by BomberBot.
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
- `Channel#close` now always wakes publishers waiting for capacity, so they
  raise the closed error even when an `on_dead_letter` callback raises during
  the force-nack. Previously such a publisher stayed blocked forever with
  `timeout: nil` (#43).
- `DeliveryTracker#on_complete`, `#on_resolved` and `#on_dead_letter` now add
  a callback instead of replacing the previous one. Hooking the tracker that
  `publish` returns no longer replaces the channel's own bookkeeping, which left
  the tracker pending, skipped the `delivered` stat, and on a bounded channel
  blocked the next `publish` forever (#50).
- `Channel#publish` and `MessageBus#publish` YARD now document the `nil`
  return when there are no subscribers, and the `throttle` params list the
  accepted `Numeric`/`nil` values (#42).
- Closing a channel from a subscriber handler while `publish` is still fanning
  out no longer leaves the remaining subscribers' deliveries pending. They are
  nacked into the dead letter queue instead of being dispatched (#48).
- `Configuration#log_level=` now rejects an invalid level before storing it.
  Previously a bad level was stored anyway, leaving `log_level` out of step
  with the logger, or raising only later at `logger=` (#74).

### Changed

- **Breaking:** Ruby 4.0 or newer is required
  (`required_ruby_version = ">= 4.0"`, previously `>= 3.2.0`). Support for
  Ruby 3.2 and 3.3 is dropped, and CI runs on Ruby 4.0 only.
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
- Refreshed the development `Gemfile.lock` with a full `bundle update`
  (minitest 6.1, rake 13.4, simplecov 1.3, rdoc 8.1, prism 2.1) (#41).
- Removed the no-op `Configuration#initialize_copy` override (#21).
- `Channel#publish` is split into small private steps, and repeated lookups
  in `Channel`, `DeliveryTracker` and `MessageBus` are tidied. No public API
  or behaviour change.
- Development tasks now run through asgard (`.loki`, importing the shared
  task files from the sibling `dev` repository) instead of Rake. The
  `Rakefile` and the `rake` development dependency are removed; CI runs the
  suite with plain `ruby`.
- The documentation now states what `<channel>_nacked` counts and that the
  delivery counters are per delivery, not per message (#78), lists the
  `ArgumentError`s the constructors raise, and describes how publishers
  waiting on a channel are woken when it closes.

### Added

- MIT `LICENSE` file (#11); `documentation_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required` gemspec metadata (#12).
- CI workflow running the test suite plus a load smoke test outside the dev
  bundle (#20); Dependabot configuration (#15), with its update PRs
  targeting the `develop` branch (#40).
- `llms.txt`, a summary of the gem for LLM readers (#65), also served from
  the docs site at `/typed_bus/llms.txt` (#77).
- `examples/15_performance.rb`, a live terminal dashboard of throughput,
  memory and GC built on `ratatui_ruby` (optional `:extras` bundle group).
- Quality gates run with `asgard quality`: RuboCop, Flog, Flay, Reek, typos,
  bundler-audit, Exhale and SCRAP, configured by `.rubocop.yml`, `.reek.yml`
  and `_typos.toml`.

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
