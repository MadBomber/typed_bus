# frozen_string_literal: true

require "test_helper"

class DeliveryTrackerTest < Minitest::Test
  def make_tracker(subscriber_ids: [1, 2])
    TypedBus::DeliveryTracker.new(
      "payload",
      channel_name: :test,
      subscriber_ids: subscriber_ids
    )
  end

  def test_starts_not_delivered
    tracker = make_tracker
    refute tracker.fully_delivered?
    refute tracker.fully_resolved?
    assert_equal 2, tracker.pending_count
  end

  def test_single_ack_not_fully_delivered
    tracker = make_tracker
    tracker.ack(1)
    refute tracker.fully_delivered?
    refute tracker.fully_resolved?
    assert_equal 1, tracker.pending_count
  end

  def test_all_acks_means_fully_delivered
    tracker = make_tracker
    tracker.ack(1)
    tracker.ack(2)
    assert tracker.fully_delivered?
    assert tracker.fully_resolved?
    assert_equal 0, tracker.pending_count
  end

  def test_nack_prevents_fully_delivered
    tracker = make_tracker
    tracker.ack(1)
    tracker.nack(2)
    refute tracker.fully_delivered?
    assert tracker.fully_resolved?
  end

  def test_on_complete_fires_when_all_acked
    completed = false
    tracker = make_tracker
    tracker.on_complete { completed = true }
    tracker.ack(1)
    refute completed
    tracker.ack(2)
    assert completed
  end

  def test_on_complete_does_not_fire_with_nack
    completed = false
    tracker = make_tracker
    tracker.on_complete { completed = true }
    tracker.ack(1)
    tracker.nack(2)
    refute completed
  end

  def test_on_dead_letter_fires_per_nack
    dead = []
    tracker = make_tracker
    tracker.on_dead_letter { |id| dead << id }
    tracker.nack(1)
    tracker.nack(2)
    assert_equal [1, 2], dead
  end

  def test_double_resolution_raises
    tracker = make_tracker
    tracker.ack(1)
    assert_raises(RuntimeError) { tracker.ack(1) }
  end

  def test_unknown_subscriber_raises
    tracker = make_tracker
    assert_raises(ArgumentError) { tracker.ack(99) }
  end

  def test_single_subscriber
    completed = false
    tracker = make_tracker(subscriber_ids: [1])
    tracker.on_complete { completed = true }
    tracker.ack(1)
    assert tracker.fully_delivered?
    assert completed
  end

  def test_on_resolved_fires_when_all_acked
    resolved = false
    tracker = make_tracker
    tracker.on_resolved { resolved = true }
    tracker.ack(1)
    refute resolved
    tracker.ack(2)
    assert resolved
  end

  def test_on_resolved_fires_when_mixed_ack_nack
    resolved = false
    tracker = make_tracker
    tracker.on_resolved { resolved = true }
    tracker.ack(1)
    refute resolved
    tracker.nack(2)
    assert resolved
  end

  def test_on_resolved_fires_when_all_nacked
    resolved = false
    tracker = make_tracker
    tracker.on_resolved { resolved = true }
    tracker.nack(1)
    refute resolved
    tracker.nack(2)
    assert resolved
  end

  def test_on_complete_and_on_resolved_both_fire
    completed = false
    resolved = false
    tracker = make_tracker
    tracker.on_complete { completed = true }
    tracker.on_resolved { resolved = true }
    tracker.ack(1)
    tracker.ack(2)
    assert completed
    assert resolved
  end

  def test_message_attr_reader
    tracker = make_tracker
    assert_equal "payload", tracker.message
  end

  def test_channel_name_attr_reader
    tracker = make_tracker
    assert_equal :test, tracker.channel_name
  end

  def test_double_nack_raises
    tracker = make_tracker
    tracker.nack(1)
    assert_raises(RuntimeError) { tracker.nack(1) }
  end

  def test_unknown_subscriber_nack_raises
    tracker = make_tracker
    assert_raises(ArgumentError) { tracker.nack(99) }
  end

  def test_no_callbacks_does_not_raise
    tracker = make_tracker
    tracker.ack(1)
    tracker.ack(2)
    assert tracker.fully_delivered?
  end

  def test_logging_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    tracker = make_tracker
    tracker.ack(1)
    tracker.ack(2)

    assert_match(/fully delivered/, log_output.string)
  ensure
    TypedBus.logger = original
  end

  def test_logging_nack_resolution_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    tracker = make_tracker
    tracker.ack(1)
    tracker.nack(2)

    assert_match(/nack/, log_output.string)
  ensure
    TypedBus.logger = original
  end
end
