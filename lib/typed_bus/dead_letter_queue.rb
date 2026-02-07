# frozen_string_literal: true

module TypedBus
  # Stores deliveries that failed — either explicitly NACKed or timed out.
  #
  # Each Channel owns a DLQ. Failed deliveries accumulate here for
  # inspection, retry, or manual drain.
  class DeadLetterQueue
    # @param on_dead_letter [Proc, nil] optional callback fired on each push
    def initialize(&on_dead_letter)
      @entries = []
      @on_dead_letter = on_dead_letter
    end

    # Add a failed delivery.
    def push(delivery)
      @entries << delivery
      reason = delivery.timed_out? ? "timeout" : "nack"
      log(:warn, "entry added (channel=:#{delivery.channel_name}, subscriber=##{delivery.subscriber_id}, reason=#{reason}, total=#{@entries.size})")
      @on_dead_letter&.call(delivery)
    end

    def size
      @entries.size
    end

    def empty?
      @entries.empty?
    end

    # Iterate over dead letters without removing them.
    def each(&block)
      @entries.each(&block)
    end

    include Enumerable

    # Yield each dead letter and remove it from the queue.
    # @return [Array<Delivery>] the drained entries
    def drain
      drained = @entries.dup
      @entries.clear
      log(:info, "drained #{drained.size} entries")
      drained.each { |d| yield d } if block_given?
      drained
    end

    def clear!
      count = @entries.size
      @entries.clear
      log(:info, "cleared #{count} entries") if count > 0
    end

    # Register or replace the callback fired when entries arrive.
    def on_dead_letter(&block)
      @on_dead_letter = block
    end

    private

    def log(level, message)
      TypedBus.logger&.send(level, "TypedBus::DeadLetterQueue #{message}")
    end
  end
end
