# frozen_string_literal: true

require "test_helper"

class StatsTest < Minitest::Test
  def setup
    @stats = TypedBus::Stats.new
  end

  def test_starts_at_zero
    assert_equal 0, @stats[:messages]
  end

  def test_increment
    @stats.increment(:messages)
    assert_equal 1, @stats[:messages]
  end

  def test_increments_independently_per_key
    @stats.increment(:a)
    @stats.increment(:a)
    @stats.increment(:b)

    assert_equal 2, @stats[:a]
    assert_equal 1, @stats[:b]
  end

  def test_reset_sets_all_counters_to_zero
    @stats.increment(:a)
    @stats.increment(:b)
    @stats.reset!

    assert_equal 0, @stats[:a]
    assert_equal 0, @stats[:b]
  end

  def test_to_h_returns_a_snapshot_copy
    @stats.increment(:x)
    snapshot = @stats.to_h

    assert_equal({ x: 1 }, snapshot)

    @stats.increment(:x)
    assert_equal 1, snapshot[:x]
  end

  def test_data_attr_reader_exposes_internal_hash
    @stats.increment(:foo)
    assert_instance_of Hash, @stats.data
    assert_equal 1, @stats.data[:foo]
  end

  def test_increment_returns_new_value
    assert_equal 1, @stats.increment(:counter)
    assert_equal 2, @stats.increment(:counter)
    assert_equal 3, @stats.increment(:counter)
  end

  def test_reset_preserves_keys
    @stats.increment(:a)
    @stats.increment(:b)
    @stats.reset!

    assert_equal({ a: 0, b: 0 }, @stats.to_h)
  end

  def test_reset_on_empty_stats_is_noop
    @stats.reset!
    assert_equal({}, @stats.to_h)
  end
end
