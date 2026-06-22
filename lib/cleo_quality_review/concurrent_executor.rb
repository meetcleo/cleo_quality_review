# frozen_string_literal: true

require "etc"

module CleoQualityReview
  ##
  # Runs independent, blocking work items across a bounded pool of threads.
  #
  # The pool is sized to the available processor count by default, so it
  # naturally expands or contracts with the host. When there are more work
  # items than workers, the surplus waits on an internal queue and is picked
  # up as workers free up. Results are returned in the same order as the
  # input items.
  #
  # Suited to I/O-bound work such as shelling out to external tools: while a
  # worker thread blocks on a subprocess, Ruby releases the GIL so other
  # workers make real progress.
  class ConcurrentExecutor
    ##
    # Environment variable that overrides the auto-detected worker count.
    ENV_VAR = "CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"

    class << self
      ##
      # Resolve the worker count, honouring an explicit value, then the
      # environment override, then the processor count.
      # @param [Integer, nil] explicit explicit worker cap, or nil to auto-size
      # @return [Integer] resolved worker count (at least 1)
      def resolve_max_workers(explicit = nil)
        [(explicit || env_max_workers || Etc.nprocessors).to_i, 1].max
      end

      ##
      # Read the worker count from the environment, if set.
      # @return [Integer, nil] the configured count, or nil when unset/blank
      # @raise [ArgumentError] if the environment value is not an integer
      def env_max_workers
        value = ENV[ENV_VAR]
        value && !value.strip.empty? ? Integer(value) : nil
      end
    end

    ##
    # @param [Integer, nil] max_workers explicit worker cap, or nil to auto-size to cores
    def initialize(max_workers: nil)
      @max_workers = self.class.resolve_max_workers(max_workers)
    end

    ##
    # Map over +items+ concurrently, preserving input order.
    # @param [Array] items work items to process
    # @yield [item] the work performed for each item
    # @return [Array] results aligned with +items+
    def map(items, &block)
      return [] if items.empty?
      return items.map(&block) if serial?(items.size)

      process(items, &block)
    end

    private

    attr_reader :max_workers

    ##
    # Whether +item_count+ items should run serially rather than in a pool.
    # @param [Integer] item_count number of work items
    # @return [Boolean]
    def serial?(item_count)
      max_workers <= 1 || item_count == 1
    end

    ##
    # Distribute +items+ across a bounded pool of worker threads.
    # @param [Array] items work items to process
    # @yield [item] the work performed for each item
    # @return [Array] results aligned with +items+
    def process(items, &block)
      results = Array.new(items.size)
      queue = work_queue(items)
      run_workers(worker_count(results.size), queue, results, &block)
      results
    end

    ##
    # Number of workers to spawn: one per item, capped at +max_workers+.
    # @param [Integer] item_count number of work items
    # @return [Integer]
    def worker_count(item_count)
      [max_workers, item_count].min
    end

    ##
    # Spawn +count+ worker threads that drain +queue+ into +results+, and join them.
    # @param [Integer] count number of worker threads
    # @param [Thread::Queue] queue source of +[index, item]+ pairs
    # @param [Array] results destination, written by index
    # @yield [item] the work performed for each item
    # @return [void]
    def run_workers(count, queue, results, &block)
      workers = Array.new(count) { spawn_worker(queue, results, &block) }
      workers.each(&:join)
    end

    ##
    # Spawn one worker thread that drains +queue+ into +results+ by index.
    # @param [Thread::Queue] queue source of +[index, item]+ pairs
    # @param [Array] results destination, written by index
    # @yield [item] the work performed for each item
    # @return [Thread]
    def spawn_worker(queue, results)
      Thread.new do
        Thread.current.report_on_exception = false
        drain(queue) { |index, item| results[index] = yield(item) }
      end
    end

    ##
    # Build a queue of +[index, item]+ pairs for the workers to consume.
    # @param [Array] items work items to process
    # @return [Thread::Queue]
    def work_queue(items)
      queue = Thread::Queue.new
      items.size.times { |index| queue << [index, items[index]] }
      queue
    end

    ##
    # Pop work off +queue+ until it is empty, yielding each pair.
    # @param [Thread::Queue] queue source of +[index, item]+ pairs
    # @yield [index, item] the indexed work item to process
    # @return [void]
    def drain(queue)
      loop do
        yield(queue.pop(true))
      rescue ThreadError
        break
      end
    end
  end
end
