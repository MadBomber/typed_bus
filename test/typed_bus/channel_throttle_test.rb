# frozen_string_literal: true

require "test_helper"

class ChannelThrottleTest < Minitest::Test
  def make_channel(**opts)
    defaults = { timeout: 0.1 }
    TypedBus::Channel.new(:test, **defaults.merge(opts))
  end

  # --- Validation errors ---

  def test_throttle_without_max_pending_raises
    error = assert_raises(ArgumentError) do
      make_channel(throttle: 0.5)
    end
    assert_match(/requires max_pending/, error.message)
  end

  def test_throttle_at_or_above_1_raises
    error = assert_raises(ArgumentError) do
      make_channel(max_pending: 10, throttle: 1.0)
    end
    assert_match(/between 0\.0 and 1\.0/, error.message)
  end

  def test_throttle_negative_raises
    error = assert_raises(ArgumentError) do
      make_channel(max_pending: 10, throttle: -0.1)
    end
    assert_match(/between 0\.0 and 1\.0/, error.message)
  end

  # --- Backward compatibility ---

  def test_channel_without_throttle_works_normally
    channel = make_channel(max_pending: 5)
    received = []
    channel.subscribe { |d| received << d.message; d.ack! }

    Async { channel.publish("hello") }

    assert_equal ["hello"], received
  end

  def test_unbounded_channel_without_throttle_works
    channel = make_channel
    received = []
    channel.subscribe { |d| received << d.message; d.ack! }

    Async { channel.publish("hello") }

    assert_equal ["hello"], received
  end

  # --- Throttle stat recording ---

  def test_throttle_records_stat_when_active
    stats = TypedBus::Stats.new
    channel = TypedBus::Channel.new(:test,
      max_pending: 10,
      stats: stats,
      timeout: 5,
      throttle: 0.5
    )
    # Fill to >50% capacity so throttle kicks in
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    Async do
      6.times { |i| channel.publish("msg#{i}") }
      deliveries.each(&:ack!)
    end

    assert_operator stats[:test_throttled], :>=, 1
  end

  # --- Clear resets state ---

  def test_clear_resets_pending
    channel = make_channel(
      max_pending: 10,
      timeout: 1,
      throttle: 0.5
    )
    channel.subscribe { |d| d.ack! }

    Async { channel.publish("msg") }

    channel.clear!
    assert_equal 0, channel.pending_count
  end

  # --- Throttled channel still delivers ---

  def test_throttled_channel_delivers_messages
    channel = make_channel(
      max_pending: 10,
      timeout: 1,
      throttle: 0.5
    )
    received = []
    channel.subscribe { |d| received << d.message; d.ack! }

    Async do
      5.times { |i| channel.publish("msg#{i}") }
    end

    assert_equal 5, received.size
  end

  # --- Backoff only activates past threshold ---

  def test_throttle_only_activates_past_threshold
    stats = TypedBus::Stats.new
    channel = TypedBus::Channel.new(:test,
      max_pending: 10,
      stats: stats,
      timeout: 5,
      throttle: 0.5
    )
    channel.subscribe { |d| d.ack! }

    # With max_pending=10 and immediate acks, pending never exceeds 1.
    # 1 pending = 90% remaining, well above 50% threshold.
    Async do
      3.times { channel.publish("msg") }
    end

    assert_equal 0, stats[:test_throttled]
  end

  # --- Custom threshold ---

  def test_custom_throttle_threshold
    stats = TypedBus::Stats.new
    channel = TypedBus::Channel.new(:test,
      max_pending: 10,
      stats: stats,
      timeout: 5,
      throttle: 0.8
    )
    # throttle at 80% remaining — even 3 pending (70% remaining) should trigger
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    Async do
      4.times { |i| channel.publish("msg#{i}") }
      deliveries.each(&:ack!)
    end

    assert_operator stats[:test_throttled], :>=, 1
  end

  # --- Throttle delay measurable ---

  def test_throttle_delay_measurably_slows_publishes
    channel = TypedBus::Channel.new(:test,
      max_pending: 5,
      timeout: 5,
      throttle: 0.9  # starts throttling at 90% remaining (i.e., almost immediately)
    )
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    elapsed = nil
    Async do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      5.times { |i| channel.publish(i) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      deliveries.each(&:ack!)
    end

    # With throttle active, total time should be > 0 (delays add up)
    assert_operator elapsed, :>, 0.05, "throttle should add measurable delay"
  end

  # --- Explicit 0.0 is disabled ---

  def test_explicit_throttle_zero_is_disabled
    stats = TypedBus::Stats.new
    channel = TypedBus::Channel.new(:test,
      max_pending: 10,
      stats: stats,
      timeout: 0.1,
      throttle: 0.0
    )
    channel.subscribe { |d| d.ack! }

    Async { 3.times { channel.publish("msg") } }

    assert_equal 0, stats[:test_throttled]
  end

  # --- Throttle validation edge cases ---

  def test_throttle_exactly_1_raises
    error = assert_raises(ArgumentError) do
      make_channel(max_pending: 10, throttle: 1.0)
    end
    assert_match(/between 0\.0 and 1\.0/, error.message)
  end

  def test_throttle_above_1_raises
    error = assert_raises(ArgumentError) do
      make_channel(max_pending: 10, throttle: 1.5)
    end
    assert_match(/between 0\.0 and 1\.0/, error.message)
  end

  # --- Full capacity must not block forever ---

  def test_throttle_at_full_capacity_yields_to_backpressure
    channel = TypedBus::Channel.new(:test,
      max_pending: 1,
      timeout: 0.2,
      throttle: 0.5
    )
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    completed = false
    Async do |task|
      task.with_timeout(2) do
        # Fill to full capacity: pending == max_pending.
        channel.publish("first")

        # A second publish at full capacity must block on backpressure,
        # not sleep forever inside the throttle.
        publisher = task.async do
          channel.publish("second")
          completed = true
        end

        sleep(0.05) # let the publisher reach the throttle/backpressure point
        deliveries.shift.ack! # drain capacity so backpressure can release the publisher

        publisher.wait
      end
    rescue Async::TimeoutError
      # completed stays false — the publisher hung at full capacity
    end

    assert completed,
      "publisher at full capacity should proceed after an ack, not sleep forever"
  end

  def test_close_during_throttle_sleep_rejects_publish
    # 7 of 10 pending leaves 30% remaining, below the 50% threshold,
    # so the next publish sleeps about 0.33s before delivering.
    channel = make_channel(max_pending: 10, throttle: 0.5, timeout: 1)
    received = []
    channel.subscribe { |d| received << d.message } # never acks

    error = nil
    Async do |task|
      task.with_timeout(2) do
        7.times { |i| channel.publish(i) }
        publisher = task.async do
          channel.publish(:late)
        rescue RuntimeError => e
          error = e
        end

        sleep(0.05) # publisher is now inside the throttle sleep
        channel.close
        publisher.wait
        sleep(0.01)
      end
    end

    assert_match(/Channel :test is closed/, error&.message)
    refute_includes received, :late
    assert_equal 0, channel.pending_count
  end

  # --- Integer coercion ---

  def test_throttle_integer_coerced_to_float
    # throttle: 0 should be treated as 0.0 (disabled)
    stats = TypedBus::Stats.new
    channel = make_channel(max_pending: 2, throttle: 0, stats: stats)
    held = []
    channel.subscribe { |d| held << d }

    Async do
      # Fill to capacity without acking: an active throttle would back off here.
      2.times { |i| channel.publish(i) }
      held.each(&:ack!)
    end

    assert_equal 2, stats[:test_delivered]
    assert_equal 0, stats[:test_throttled]
  end
end
