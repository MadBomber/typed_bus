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

    # Remove the current entries from the queue and yield each one once.
    #
    # The queue is emptied before the first yield, so while the block
    # runs, #size and #each see only entries added during the drain.
    # Those (such as a retry that fails again) stay queued for the next
    # drain. If the block raises, the entry it was handling and the ones
    # not yet yielded go back to the front of the queue in their
    # original order. If the block exits early with +break+, +return+,
    # or +throw+, the entry it was handling counts as done and only the
    # ones not yet yielded go back.
    # @return [Array<Delivery>] the drained entries
    def drain
      drained, @entries = @entries, []
      if block_given?
        handled = 0
        begin
          drained.each do |entry|
            handled += 1
            yield entry
          end
        rescue Exception # rubocop:disable Lint/RescueException -- any raise puts the entry back
          handled -= 1
          raise
        ensure
          @entries.unshift(*drained.drop(handled))
        end
      end
      log(:info, "drained #{drained.size} entries")
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
