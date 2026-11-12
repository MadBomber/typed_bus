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
    # The drain works on a snapshot taken when it starts. Entries added
    # while the block runs (for example, a retry that fails again and
    # lands back in this queue) are not yielded; they stay queued for
    # the next drain. Calling #clear! inside the block does not affect
    # the entries being drained.
    #
    # If the block raises, the entry it was handling and every entry not
    # yet yielded go back to the front of the queue, in their original
    # order, ahead of anything added during the drain.
    # @return [Array<Delivery>] the drained entries
    def drain
      drained = @entries.dup
      @entries.clear
      if block_given?
        yielded = 0
        begin
          drained.each do |entry|
            yield entry
            yielded += 1
          end
        ensure
          @entries.unshift(*drained.drop(yielded))
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
