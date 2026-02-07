# frozen_string_literal: true

require "test_helper"

class MessageBusTest < Minitest::Test
  def setup
    @bus = TypedBus::MessageBus.new
  end

  def test_add_channel_registers_a_channel
    @bus.add_channel(:events)

    assert @bus.channel?(:events)
    refute @bus.channel?(:missing)
  end

  def test_channel_names_lists_registered_channels
    @bus.add_channel(:a)
    @bus.add_channel(:b)

    assert_equal %i[a b].sort, @bus.channel_names.sort
  end

  def test_publish_and_subscribe_deliver_messages
    @bus.add_channel(:queue, timeout: 1)
    received = []
    @bus.subscribe(:queue) { |d| received << d.message; d.ack! }

    Async { @bus.publish(:queue, "hello") }

    assert_equal ["hello"], received
  end

  def test_publish_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.publish(:nope, "x") }
    assert_match(/Unknown channel/, error.message)
  end

  def test_publish_tracks_stats_per_channel
    @bus.add_channel(:events, timeout: 1)
    @bus.subscribe(:events) { |d| d.ack! }

    Async do
      @bus.publish(:events, "a")
      @bus.publish(:events, "b")
    end

    assert_equal 2, @bus.stats[:events_published]
  end

  def test_subscribe_notifies_across_channels
    @bus.add_channel(:a, timeout: 1)
    @bus.add_channel(:b, timeout: 1)

    a_msgs = []
    b_msgs = []
    @bus.subscribe(:a) { |d| a_msgs << d.message; d.ack! }
    @bus.subscribe(:b) { |d| b_msgs << d.message; d.ack! }

    Async do
      @bus.publish(:a, "x")
      @bus.publish(:b, "y")
    end

    assert_equal ["x"], a_msgs
    assert_equal ["y"], b_msgs
  end

  def test_pending_checks_channel_deliveries
    @bus.add_channel(:q, timeout: 0.1)
    @bus.subscribe(:q) { |_d| } # never acks

    Async do
      @bus.publish(:q, "msg")
      assert @bus.pending?(:q)
    end
  end

  def test_remove_channel_closes_and_removes
    @bus.add_channel(:temp)
    @bus.remove_channel(:temp)

    refute @bus.channel?(:temp)
  end

  def test_clear_resets_channels_and_stats
    @bus.add_channel(:q, timeout: 1)
    @bus.subscribe(:q) { |d| d.ack! }
    Async { @bus.publish(:q, "msg") }
    @bus.clear!

    refute @bus.pending?(:q)
    assert_equal 0, @bus.stats[:q_published]
  end

  def test_dead_letters_accesses_channel_dlq
    @bus.add_channel(:q, timeout: 1)
    Async { @bus.publish(:q, "orphan") } # no subscribers

    dlq = @bus.dead_letters(:q)
    assert_equal 1, dlq.size
  end

  def test_close_channel
    @bus.add_channel(:q)
    @bus.close(:q)

    assert_raises(RuntimeError) { @bus.publish(:q, "nope") }
  end

  def test_close_all
    @bus.add_channel(:a)
    @bus.add_channel(:b)
    @bus.close_all

    assert_raises(RuntimeError) { @bus.publish(:a, "nope") }
    assert_raises(RuntimeError) { @bus.publish(:b, "nope") }
  end

  def test_pending_count
    @bus.add_channel(:q, timeout: 0.1)
    @bus.subscribe(:q) { |_d| } # never acks

    Async do
      @bus.publish(:q, "msg")
      assert_equal 1, @bus.pending_count(:q)
    end
  end

  # --- Stats counters ---

  def test_stats_delivered_when_all_ack
    @bus.add_channel(:q, timeout: 1)
    @bus.subscribe(:q) { |d| d.ack! }
    @bus.subscribe(:q) { |d| d.ack! }

    Async { @bus.publish(:q, "msg") }

    assert_equal 1, @bus.stats[:q_published]
    assert_equal 1, @bus.stats[:q_delivered]
  end

  def test_stats_nacked_on_explicit_nack
    @bus.add_channel(:q, timeout: 1)
    @bus.subscribe(:q) { |d| d.nack! }

    Async { @bus.publish(:q, "rejected") }

    assert_equal 1, @bus.stats[:q_nacked]
    assert_equal 1, @bus.stats[:q_dead_lettered]
  end

  def test_stats_timed_out
    @bus.add_channel(:q, timeout: 0.01)
    @bus.subscribe(:q) { |_d| } # never acks

    Async do
      @bus.publish(:q, "slow")
      sleep(0.05)
    end

    assert_equal 1, @bus.stats[:q_timed_out]
    assert_equal 1, @bus.stats[:q_dead_lettered]
  end

  def test_stats_dead_lettered_no_subscribers
    @bus.add_channel(:q, timeout: 1)
    Async { @bus.publish(:q, "orphan") }

    assert_equal 1, @bus.stats[:q_nacked]
    assert_equal 1, @bus.stats[:q_dead_lettered]
  end

  # --- Default throttle ---

  def test_default_throttle_applied_to_channels
    bus = TypedBus::MessageBus.new(throttle: 0.5)
    bus.add_channel(:orders, max_pending: 100, timeout: 1)
    bus.subscribe(:orders) { |d| d.ack! }
    Async { bus.publish(:orders, "msg") }

    assert_equal 1, bus.stats[:orders_published]
  end

  def test_channel_can_override_default_throttle
    bus = TypedBus::MessageBus.new(throttle: 0.5)
    bus.add_channel(:fast, max_pending: 200, timeout: 1, throttle: 0.0)
    bus.subscribe(:fast) { |d| d.ack! }
    Async { bus.publish(:fast, "msg") }

    assert_equal 1, bus.stats[:fast_published]
  end

  def test_bus_without_default_throttle_channels_have_no_throttle
    bus = TypedBus::MessageBus.new
    bus.add_channel(:plain, timeout: 1)
    bus.subscribe(:plain) { |d| d.ack! }
    Async { bus.publish(:plain, "msg") }

    assert_equal 1, bus.stats[:plain_published]
  end

  # --- Unknown channel errors for all methods ---

  def test_subscribe_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.subscribe(:nope) { |d| d.ack! } }
    assert_match(/Unknown channel/, error.message)
  end

  def test_unsubscribe_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.unsubscribe(:nope, 1) }
    assert_match(/Unknown channel/, error.message)
  end

  def test_dead_letters_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.dead_letters(:nope) }
    assert_match(/Unknown channel/, error.message)
  end

  def test_close_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.close(:nope) }
    assert_match(/Unknown channel/, error.message)
  end

  def test_pending_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.pending?(:nope) }
    assert_match(/Unknown channel/, error.message)
  end

  def test_pending_count_raises_on_unknown_channel
    error = assert_raises(ArgumentError) { @bus.pending_count(:nope) }
    assert_match(/Unknown channel/, error.message)
  end

  # --- remove_channel on nonexistent is a no-op ---

  def test_remove_channel_nonexistent_is_noop
    @bus.remove_channel(:nonexistent) # should not raise
    refute @bus.channel?(:nonexistent)
  end

  # --- channel_names starts empty ---

  def test_channel_names_empty_initially
    bus = TypedBus::MessageBus.new
    assert_equal [], bus.channel_names
  end

  # --- stats attr_reader ---

  def test_stats_attr_reader
    assert_instance_of TypedBus::Stats, @bus.stats
  end

  # --- add_channel returns the channel ---

  def test_add_channel_returns_channel
    channel = @bus.add_channel(:returns, timeout: 1)
    assert_instance_of TypedBus::Channel, channel
    assert_equal :returns, channel.name
  end

  # --- unsubscribe passthrough ---

  def test_unsubscribe_passthrough
    @bus.add_channel(:q, timeout: 1)
    received = []
    id = @bus.subscribe(:q) { |d| received << d.message; d.ack! }

    Async { @bus.publish(:q, "before") }

    @bus.unsubscribe(:q, id)

    Async { @bus.publish(:q, "after") }

    assert_equal ["before"], received
  end

  # --- close_all on empty bus ---

  def test_close_all_on_empty_bus
    bus = TypedBus::MessageBus.new
    bus.close_all  # should not raise
  end

  # --- clear on empty bus ---

  def test_clear_on_empty_bus
    bus = TypedBus::MessageBus.new
    bus.clear!  # should not raise
    assert_equal({}, bus.stats.to_h)
  end

  # --- channel? returns false for removed channels ---

  def test_channel_false_after_removal
    @bus.add_channel(:temp)
    assert @bus.channel?(:temp)
    @bus.remove_channel(:temp)
    refute @bus.channel?(:temp)
  end

  # --- Type enforcement via bus ---

  def test_typed_channel_via_bus
    @bus.add_channel(:typed, type: String, timeout: 1)
    @bus.subscribe(:typed) { |d| d.ack! }

    error = assert_raises(ArgumentError) { @bus.publish(:typed, 42) }
    assert_match(/Expected String/, error.message)
  end

  def test_logging_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    bus = TypedBus::MessageBus.new
    bus.add_channel(:logged, timeout: 1)
    bus.subscribe(:logged) { |d| d.ack! }
    Async { bus.publish(:logged, "msg") }

    assert_match(/message bus initialized/, log_output.string)
    assert_match(/adding channel/, log_output.string)
  ensure
    TypedBus.logger = original
  end
end
