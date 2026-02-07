# frozen_string_literal: true

require "test_helper"

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
