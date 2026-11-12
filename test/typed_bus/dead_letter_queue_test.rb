# frozen_string_literal: true

require "test_helper"
require "timeout"

class DeadLetterQueueTest < Minitest::Test
  def make_delivery(msg = "payload")
    TypedBus::Delivery.new(msg, channel_name: :test, subscriber_id: 1)
  end

  def test_starts_empty
    dlq = TypedBus::DeadLetterQueue.new
    assert dlq.empty?
    assert_equal 0, dlq.size
  end

  def test_push_adds_entry
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery)
    refute dlq.empty?
    assert_equal 1, dlq.size
  end

  def test_each_iterates_entries
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery("a"))
    dlq.push(make_delivery("b"))

    messages = dlq.map(&:message)
    assert_equal %w[a b], messages
  end

  def test_drain_removes_and_returns_entries
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery("a"))
    dlq.push(make_delivery("b"))

    drained = dlq.drain
    assert_equal %w[a b], drained.map(&:message)
    assert dlq.empty?
  end

  def test_drain_with_block_yields_each
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery("x"))

    yielded = []
    dlq.drain { |d| yielded << d.message }
    assert_equal ["x"], yielded
    assert dlq.empty?
  end

  def test_drain_block_raise_keeps_unprocessed_entries
    dlq = TypedBus::DeadLetterQueue.new
    %w[a b c d e].each { |m| dlq.push(make_delivery(m)) }

    processed = []
    assert_raises(RuntimeError) do
      dlq.drain do |d|
        raise "boom" if d.message == "c"

        processed << d.message
      end
    end

    # "c" raised, so "c", "d", "e" remain in the queue for a retry.
    assert_equal %w[a b], processed
    assert_equal %w[c d e], dlq.map(&:message)
    assert_equal 3, dlq.size
  end

  # Raise once a drain block has run more than +limit+ times, so a
  # drain that never ends fails the test instead of hanging the suite.
  def guard_calls(calls, limit = 10)
    raise "drain looped: #{calls} calls" if calls > limit
  end

  def test_drain_block_pushing_entry_back_yields_it_once
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery("a"))

    calls = 0
    drained = Timeout.timeout(1) do
      dlq.drain do |d|
        guard_calls(calls += 1)
        dlq.push(d)
      end
    end

    assert_equal 1, calls
    assert_equal %w[a], drained.map(&:message)
    assert_equal %w[a], dlq.map(&:message)
  end

  def test_drain_block_calling_clear_returns_all_entries
    dlq = TypedBus::DeadLetterQueue.new
    %w[a b].each { |m| dlq.push(make_delivery(m)) }

    yielded = []
    drained = Timeout.timeout(1) do
      dlq.drain do |d|
        guard_calls(yielded.size)
        yielded << d.message
        dlq.clear!
      end
    end

    assert_equal %w[a b], yielded
    assert_equal %w[a b], drained.map(&:message)
    assert dlq.empty?
  end

  def test_drain_block_raise_restores_unprocessed_ahead_of_new_entries
    dlq = TypedBus::DeadLetterQueue.new
    %w[a b c].each { |m| dlq.push(make_delivery(m)) }

    assert_raises(RuntimeError) do
      dlq.drain do |d|
        dlq.push(make_delivery("new"))
        raise "boom" if d.message == "b"
      end
    end

    assert_equal %w[b c new new], dlq.map(&:message)
  end

  def test_drain_block_republishing_without_subscribers_runs_once
    Sync do
      channel = TypedBus::Channel.new(:retry, timeout: nil)
      channel.publish("m")
      assert_equal 1, channel.dead_letter_queue.size

      calls = 0
      channel.dead_letter_queue.drain do |d|
        guard_calls(calls += 1)
        channel.publish(d.message)
      end

      assert_equal 1, calls
      assert_equal %w[m], channel.dead_letter_queue.map(&:message)
    end
  end

  def test_clear_empties_queue
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery)
    dlq.clear!
    assert dlq.empty?
  end

  def test_on_dead_letter_callback_fires_on_push
    received = []
    dlq = TypedBus::DeadLetterQueue.new { |d| received << d.message }
    dlq.push(make_delivery("fail1"))
    dlq.push(make_delivery("fail2"))
    assert_equal %w[fail1 fail2], received
  end

  def test_on_dead_letter_can_be_set_after_construction
    received = []
    dlq = TypedBus::DeadLetterQueue.new
    dlq.on_dead_letter { |d| received << d.message }
    dlq.push(make_delivery("late"))
    assert_equal ["late"], received
  end

  def test_on_dead_letter_replaces_previous_callback
    first_received = []
    second_received = []
    dlq = TypedBus::DeadLetterQueue.new { |d| first_received << d.message }
    dlq.on_dead_letter { |d| second_received << d.message }
    dlq.push(make_delivery("test"))
    assert_empty first_received
    assert_equal ["test"], second_received
  end

  def test_clear_on_empty_queue_is_noop
    dlq = TypedBus::DeadLetterQueue.new
    dlq.clear!
    assert dlq.empty?
  end

  def test_drain_on_empty_returns_empty_array
    dlq = TypedBus::DeadLetterQueue.new
    result = dlq.drain
    assert_equal [], result
  end

  def test_enumerable_methods_work
    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery("a"))
    dlq.push(make_delivery("b"))
    dlq.push(make_delivery("c"))

    assert_equal 3, dlq.count
    assert_equal "a", dlq.first.message
    messages = dlq.select { |d| d.message > "a" }.map(&:message)
    assert_equal %w[b c], messages
  end

  def test_logging_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    dlq = TypedBus::DeadLetterQueue.new
    dlq.push(make_delivery("fail"))

    assert_match(/entry added/, log_output.string)
  ensure
    TypedBus.logger = original
  end
end
