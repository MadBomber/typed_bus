# frozen_string_literal: true

require "test_helper"

class DeliveryTest < Minitest::Test
  def make_delivery(**opts)
    defaults = { channel_name: :test, subscriber_id: 1 }
    TypedBus::Delivery.new("payload", **defaults.merge(opts))
  end

  def test_starts_pending
    d = make_delivery
    assert d.pending?
    refute d.acked?
    refute d.nacked?
  end

  def test_ack_transitions_state
    d = make_delivery
    d.ack!
    assert d.acked?
    refute d.pending?
    refute d.nacked?
  end

  def test_nack_transitions_state
    d = make_delivery
    d.nack!
    assert d.nacked?
    refute d.pending?
    refute d.acked?
  end

  def test_double_ack_raises
    d = make_delivery
    d.ack!
    assert_raises(RuntimeError) { d.ack! }
  end

  def test_ack_then_nack_raises
    d = make_delivery
    d.ack!
    assert_raises(RuntimeError) { d.nack! }
  end

  def test_nack_then_ack_raises
    d = make_delivery
    d.nack!
    assert_raises(RuntimeError) { d.ack! }
  end

  def test_ack_fires_on_ack_callback
    called_with = nil
    d = make_delivery(subscriber_id: 42, on_ack: ->(id) { called_with = id })
    d.ack!
    assert_equal 42, called_with
  end

  def test_nack_fires_on_nack_callback
    called_with = nil
    d = make_delivery(subscriber_id: 7, on_nack: ->(id) { called_with = id })
    d.nack!
    assert_equal 7, called_with
  end

  def test_exposes_message_and_channel_name
    d = make_delivery(channel_name: :events)
    assert_equal "payload", d.message
    assert_equal :events, d.channel_name
  end

  def test_timeout_auto_nacks
    nacked_id = nil
    Async do
      d = make_delivery(
        timeout: 0.01,
        on_nack: ->(id) { nacked_id = id }
      )
      sleep(0.05)
      assert d.nacked?
    end
    assert_equal 1, nacked_id
  end

  def test_ack_before_timeout_cancels_timer
    Async do
      d = make_delivery(timeout: 0.05)
      d.ack!
      sleep(0.1)
      assert d.acked?
    end
  end

  def test_timed_out_flag
    Async do
      d = make_delivery(timeout: 0.01)
      refute d.timed_out?
      sleep(0.05)
      assert d.timed_out?
      assert d.nacked?
    end
  end

  def test_explicit_nack_is_not_timed_out
    d = make_delivery
    d.nack!
    refute d.timed_out?
  end

  def test_nack_cancels_timeout_task
    Async do
      nack_count = 0
      d = make_delivery(
        timeout: 0.05,
        on_nack: ->(_id) { nack_count += 1 }
      )
      d.nack!
      sleep(0.1) # wait past timeout
      assert_equal 1, nack_count, "on_nack should fire only once — nack! must cancel timeout"
    end
  end

  def test_cancel_timeout_without_timeout_is_noop
    d = make_delivery # no timeout set
    d.cancel_timeout  # should not raise
    assert d.pending?
  end

  def test_subscriber_id_attr_reader
    d = make_delivery(subscriber_id: 99)
    assert_equal 99, d.subscriber_id
  end

  def test_no_callbacks_does_not_raise
    d = make_delivery # on_ack and on_nack are nil
    d.ack!
    assert d.acked?
  end

  def test_nack_without_callbacks_does_not_raise
    d = make_delivery
    d.nack!
    assert d.nacked?
  end

  def test_timeout_skips_when_already_resolved
    Async do
      nack_count = 0
      d = make_delivery(
        timeout: 0.05,
        on_nack: ->(_id) { nack_count += 1 }
      )
      d.ack!
      sleep(0.1) # wait past timeout — timeout fiber should `next` (skip)
      assert d.acked?
      assert_equal 0, nack_count
    end
  end

  def test_logging_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    d = make_delivery
    d.ack!

    assert_match(/acked/, log_output.string)
  ensure
    TypedBus.logger = original
  end

  def test_logging_nack_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    d = make_delivery
    d.nack!

    assert_match(/nacked/, log_output.string)
  ensure
    TypedBus.logger = original
  end

  def test_logging_timeout_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    Async do
      d = make_delivery(timeout: 0.01)
      sleep(0.05)
      assert d.nacked?
    end

    assert_match(/timed out/, log_output.string)
  ensure
    TypedBus.logger = original
  end

  def test_timeout_guard_skips_when_already_resolved_before_sleep_ends
    # Exercises the `next unless pending?` branch inside start_timeout.
    # We create a delivery with a timeout, then resolve it via nack!
    # *without* cancelling the timeout task, so the timeout fiber wakes
    # and finds the delivery already resolved.
    Async do
      nack_count = 0
      d = TypedBus::Delivery.new("payload",
        channel_name: :test,
        subscriber_id: 1,
        timeout: 0.03,
        on_nack: ->(_id) { nack_count += 1 }
      )
      # Directly transition state without cancelling the timeout task.
      # Simulate a resolution that leaves the timeout fiber alive.
      d.instance_variable_set(:@state, :nacked)

      sleep(0.06) # let the timeout fiber wake up and hit `next unless pending?`
      assert_equal 0, nack_count, "timeout should skip when already resolved"
    end
  end
end
