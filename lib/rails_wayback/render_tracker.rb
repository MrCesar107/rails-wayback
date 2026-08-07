# frozen_string_literal: true

module RailsWayback
  # Collects render events for one request. A tracker can be shared with
  # child execution contexts while keeping mutation and closure atomic.
  class RenderTracker
    def initialize
      @entries = []
      @mutex = Mutex.new
      @closed = false
    end

    def record(event:, identifier:)
      @mutex.synchronize do
        next false if @closed

        @entries << { event: event.to_s, identifier: identifier.to_s }.freeze
        true
      end
    end

    def entries
      @mutex.synchronize { @entries.dup }
    end

    def close
      @mutex.synchronize { @closed = true }
    end

    def closed?
      @mutex.synchronize { @closed }
    end
  end
end
