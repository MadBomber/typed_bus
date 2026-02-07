# frozen_string_literal: true

require "test_helper"

class ChannelTest < Minitest::Test
  TestEvent = Data.define(:name, :payload)

  def make_channel(**opts)
    defaults = { timeout: 0.1 }
    TypedBus::Channel.new(:test, **defaults.merge(opts))
  end

  # --- Type constraints ---

  def test_untyped_channel_accepts_any_message_type
    channel = make_channel
    received = []
    channel.subscribe { |d| received << d.message; d.ack! }

    Async do
      channel.publish("hello")
      channel.publish(42)
      channel.publish({ key: "val" })
    end

    assert_equal ["hello", 42, { key: "val" }], received
  end

  def test_typed_channel_accepts_correct_type
    channel = make_channel(type: TestEvent)
    received = []
    channel.subscribe { |d| received << d.message; d.ack! }

    event = TestEvent.new(name: "test", payload: "data")
    Async { channel.publish(event) }

    assert_equal [event], received
  end

  def test_typed_channel_rejects_wrong_type
    channel = make_channel(type: TestEvent)

    error = assert_raises(ArgumentError) { channel.publish("not an event") }
    assert_match(/Expected ChannelTest::TestEvent/, error.message)
  end

  # --- Pub/sub delivery ---

  def test_subscribe_receives_delivery_objects
    channel = make_channel
    deliveries = []
    channel.subscribe { |d| deliveries << d; d.ack! }

    Async { channel.publish("msg") }

    assert_equal 1, deliveries.size
    assert_instance_of TypedBus::Delivery, deliveries.first
    assert_equal "msg", deliveries.first.message
  end

  def test_multiple_subscribers_each_get_delivery
    channel = make_channel
    a_msgs = []
    b_msgs = []
    channel.subscribe { |d| a_msgs << d.message; d.ack! }
    channel.subscribe { |d| b_msgs << d.message; d.ack! }

    Async { channel.publish("shared") }

    assert_equal ["shared"], a_msgs
    assert_equal ["shared"], b_msgs
  end

  def test_subscriber_error_does_not_crash_publish
    channel = make_channel
    channel.subscribe { raise "boom" }

    Async { channel.publish("ok") }
    # should not raise — error is warned and delivery is nacked
  end

  def test_subscriber_error_nacks_delivery
    channel = make_channel
    channel.subscribe { raise "boom" }

    Async { channel.publish("ok") }

    assert_equal 1, channel.dead_letter_queue.size
  end

  # --- Unsubscribe ---

  def test_unsubscribe_by_id
    channel = make_channel
    received = []
    id = channel.subscribe { |d| received << d.message; d.ack! }

    Async { channel.publish("before") }
    channel.unsubscribe(id)
    Async { channel.publish("after") }

    assert_equal ["before"], received
  end

  def test_unsubscribe_by_block
    channel = make_channel
    received = []
    handler = ->(d) { received << d.message; d.ack! }
    channel.subscribe(&handler)

    Async { channel.publish("before") }
    channel.unsubscribe(handler)
    Async { channel.publish("after") }

    assert_equal ["before"], received
  end

  # --- No subscribers → DLQ ---

  def test_publish_with_no_subscribers_goes_to_dlq
    channel = make_channel
    Async { channel.publish("orphan") }

    assert_equal 1, channel.dead_letter_queue.size
    assert_equal "orphan", channel.dead_letter_queue.first.message
  end

  # --- Nack goes to DLQ ---

  def test_nacked_delivery_goes_to_dlq
    channel = make_channel
    channel.subscribe { |d| d.nack! }

    Async { channel.publish("rejected") }

    assert_equal 1, channel.dead_letter_queue.size
    assert_equal "rejected", channel.dead_letter_queue.first.message
  end

  # --- Timeout goes to DLQ ---

  def test_timeout_sends_to_dlq
    channel = make_channel(timeout: 0.01)
    channel.subscribe { |_d| } # never acks

    Async do
      channel.publish("slow")
      sleep(0.05)
    end

    assert_equal 1, channel.dead_letter_queue.size
  end

  # --- Pending tracking ---

  def test_pending_count_tracks_unresolved
    channel = make_channel(timeout: 1)
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    Async do
      channel.publish("a")

      assert_equal 1, channel.pending_count
      assert channel.pending?

      deliveries.first.ack!

      refute channel.pending?
      assert_equal 0, channel.pending_count
    end
  end

  # --- Lifecycle ---

  def test_closed_channel_rejects_publish
    channel = make_channel
    channel.close
    assert channel.closed?
    assert_raises(RuntimeError) { channel.publish("nope") }
  end

  def test_closed_channel_rejects_subscribe
    channel = make_channel
    channel.close
    assert_raises(RuntimeError) { channel.subscribe { |d| d.ack! } }
  end

  def test_clear_empties_pending_and_dlq
    channel = make_channel(timeout: 1)
    channel.subscribe { |_d| } # never acks

    Async { channel.publish("msg") }

    channel.dead_letter_queue.push(
      TypedBus::Delivery.new("old", channel_name: :test, subscriber_id: -1)
    )

    channel.clear!
    assert_equal 0, channel.pending_count
    assert channel.dead_letter_queue.empty?
  end

  # --- Subscriber count ---

  def test_subscriber_count
    channel = make_channel
    assert_equal 0, channel.subscriber_count

    id = channel.subscribe { |d| d.ack! }
    assert_equal 1, channel.subscriber_count

    channel.unsubscribe(id)
    assert_equal 0, channel.subscriber_count
  end

  # --- P0/P1 fix regression tests ---

  def test_tracker_removed_after_nack
    channel = make_channel(timeout: 1)
    channel.subscribe { |d| d.nack! }

    Async { channel.publish("rejected") }

    assert_equal 0, channel.pending_count, "tracker must be removed even when subscriber nacks"
  end

  def test_close_force_nacks_pending_deliveries
    channel = make_channel(timeout: 1)
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    Async do
      channel.publish("msg")

      assert_equal 1, channel.pending_count
      channel.close

      assert deliveries.first.nacked?, "pending delivery should be nacked on close"
      assert_equal 0, channel.pending_count
      assert_equal 1, channel.dead_letter_queue.size
    end
  end

  def test_clear_cancels_timeout_tasks
    channel = make_channel(timeout: 0.05)
    channel.subscribe { |_d| } # never acks

    Async do
      channel.publish("msg")
      channel.clear!
      sleep(0.1) # wait past timeout
    end

    # DLQ was cleared, and no new entries from orphaned timeouts
    assert channel.dead_letter_queue.empty?
  end

  # --- Backpressure ---

  def test_bounded_channel_blocks_publisher_at_capacity
    channel = make_channel(max_pending: 1, timeout: 1)
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    publish_order = []

    Async do
      Async do
        channel.publish("first")
        publish_order << :first_done

        channel.publish("second") # should block
        publish_order << :second_done
      end

      # Let first publish dispatch
      sleep(0.01)

      # At this point, "first" is pending, "second" should be blocked
      assert_equal [:first_done], publish_order
      assert_equal 1, channel.pending_count

      # ACK the first delivery to unblock
      deliveries.first.ack!
      sleep(0.01)

      assert_equal [:first_done, :second_done], publish_order
    end
  end

  # --- Attr readers ---

  def test_name_attr_reader
    channel = make_channel
    assert_equal :test, channel.name
  end

  def test_type_attr_reader
    channel = make_channel(type: String)
    assert_equal String, channel.type
  end

  def test_type_attr_reader_nil_when_untyped
    channel = make_channel
    assert_nil channel.type
  end

  def test_dead_letter_queue_attr_reader
    channel = make_channel
    assert_instance_of TypedBus::DeadLetterQueue, channel.dead_letter_queue
  end

  # --- Publish return values ---

  def test_publish_returns_delivery_tracker
    channel = make_channel
    channel.subscribe { |d| d.ack! }

    tracker = nil
    Async { tracker = channel.publish("msg") }

    assert_instance_of TypedBus::DeliveryTracker, tracker
  end

  def test_publish_returns_nil_with_no_subscribers
    channel = make_channel

    result = nil
    Async { result = channel.publish("orphan") }

    assert_nil result
  end

  # --- Close idempotency ---

  def test_close_is_idempotent
    channel = make_channel
    channel.close
    channel.close  # should not raise
    assert channel.closed?
  end

  # --- Subscriber count edge cases ---

  def test_subscriber_count_after_multiple_adds_and_removes
    channel = make_channel
    id1 = channel.subscribe { |d| d.ack! }
    id2 = channel.subscribe { |d| d.ack! }
    id3 = channel.subscribe { |d| d.ack! }
    assert_equal 3, channel.subscriber_count

    channel.unsubscribe(id2)
    assert_equal 2, channel.subscriber_count

    channel.unsubscribe(id1)
    channel.unsubscribe(id3)
    assert_equal 0, channel.subscriber_count
  end

  # --- Subscribe returns sequential ids ---

  def test_subscribe_returns_incrementing_ids
    channel = make_channel
    id1 = channel.subscribe { |d| d.ack! }
    id2 = channel.subscribe { |d| d.ack! }
    id3 = channel.subscribe { |d| d.ack! }

    assert_equal 1, id1
    assert_equal 2, id2
    assert_equal 3, id3
  end

  # --- Stats integration ---

  def test_channel_without_stats_does_not_raise
    channel = TypedBus::Channel.new(:nostats, timeout: 0.1)
    channel.subscribe { |d| d.ack! }

    Async { channel.publish("msg") }
    # no error even without stats
  end

  def test_stats_recording_published_counter
    stats = TypedBus::Stats.new
    channel = TypedBus::Channel.new(:counted, timeout: 0.1, stats: stats)
    channel.subscribe { |d| d.ack! }

    Async do
      channel.publish("a")
      channel.publish("b")
    end

    assert_equal 2, stats[:counted_delivered]
  end

  # --- Pending edge cases ---

  def test_pending_false_when_no_messages
    channel = make_channel
    channel.subscribe { |d| d.ack! }
    refute channel.pending?
    assert_equal 0, channel.pending_count
  end

  # --- Subscriber removed between snapshot and delivery ---

  def test_subscriber_removed_during_publish_iteration
    channel = make_channel(timeout: 1)
    received = []

    # First subscriber unsubscribes the second during its callback
    id2 = nil
    channel.subscribe do |d|
      channel.unsubscribe(id2)
      received << :first
      d.ack!
    end
    id2 = channel.subscribe do |d|
      received << :second
      d.ack!
    end

    Async { channel.publish("msg") }

    # First subscriber ran; second was unsubscribed mid-iteration
    # The handler lookup returns nil, so `next unless handler` fires
    assert_includes received, :first
  end

  # --- Subscriber error when delivery already resolved ---

  def test_subscriber_error_after_nack_skips_double_nack
    channel = make_channel(timeout: 1)
    channel.subscribe do |d|
      d.nack!
      raise "error after nack"
    end

    Async { channel.publish("msg") }

    # delivery.pending? is false in rescue, so the if-else branch is hit
    assert_equal 1, channel.dead_letter_queue.size
  end

  # --- Close with mix of resolved and pending deliveries ---

  def test_close_skips_already_resolved_deliveries
    channel = make_channel(timeout: 1)
    deliveries = []
    channel.subscribe { |d| deliveries << d }

    Async do
      channel.publish("a")
      channel.publish("b")

      # Resolve first, leave second pending
      deliveries.first.ack!

      channel.close

      # Second was force-nacked, first was already resolved (else branch)
      assert deliveries[0].acked?
      assert deliveries[1].nacked?
    end
  end

  # --- force_nack_pending skips resolved deliveries ---

  def test_force_nack_skips_already_resolved_delivery
    channel = make_channel(timeout: 1)
    channel.subscribe { |d| d.ack! }

    Async do
      channel.publish("msg")

      # Inject a pre-resolved delivery into active_deliveries
      # to exercise the `else` branch of `delivery.nack! if delivery.pending?`
      resolved = TypedBus::Delivery.new("already_done", channel_name: :test, subscriber_id: -1)
      resolved.nack!
      channel.instance_variable_get(:@active_deliveries) << resolved

      channel.close

      # The resolved delivery should not raise (double nack), close succeeds
      assert channel.closed?
    end
  end

  # --- Logging when logger is set ---

  def test_logging_when_logger_set
    log_output = StringIO.new
    original = TypedBus.logger
    TypedBus.logger = Logger.new(log_output)

    channel = make_channel
    channel.subscribe { |d| d.ack! }
    Async { channel.publish("msg") }

    assert_match(/channel created/, log_output.string)
    assert_match(/published message/, log_output.string)
  ensure
    TypedBus.logger = original
  end
end
