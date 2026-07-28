# frozen_string_literal: true

require_relative "../../test_helper"
require "timeout"
require "cleo_quality_review/concurrent_executor"

module CleoQualityReview
  ##
  # Exercises ordered concurrent mapping and worker-count limits.
  class ConcurrentExecutorTest < Minitest::Test
    # Coordinates a concurrent run so a test can observe how many items run at
    # once: each mapped item reports that it started, then blocks until released.
    Gate = Struct.new(:started, :release, :executor, :items) do
      def self.for(executor, items)
        new(Thread::Queue.new, Thread::Queue.new, executor, items)
      end

      # Run +executor.map+ on a background thread, gating each item on this Gate.
      # @return [Thread] whose #value is the ordered map result
      def run(&block)
        Thread.new do
          executor.map(items) do |item|
            started << item
            release.pop
            block.call(item)
          end
        end
      end

      def await_started(count)
        Timeout.timeout(5) { count.times { started.pop } }
      end

      def release_all(count)
        count.times { release << :go }
      end

      def results_after_started(started_count, &block)
        runner = run(&block)
        await_started(started_count)
        release_all(items.size)
        runner.value
      end

      def surplus_started_after(started_count, &block)
        runner = run(&block)
        await_started(started_count)
        sleep(0.05) # let any surplus workers (a broken cap) start and signal
        started.size
      ensure
        release_all(items.size)
        runner&.value
      end
    end

    def test_returns_empty_array_for_empty_input
      assert_equal [], ConcurrentExecutor.new(max_workers: 4).map([]) { |item| item }
    end

    def test_preserves_input_order
      results = ConcurrentExecutor.new(max_workers: 4).map([1, 2, 3, 4, 5]) { |number| number * number }

      assert_equal [1, 4, 9, 16, 25], results
    end

    def test_preserves_order_even_when_later_items_finish_first
      results = ConcurrentExecutor.new(max_workers: 5).map([0.03, 0.02, 0.01, 0.0]) do |delay|
        sleep(delay)
        delay
      end

      assert_equal [0.03, 0.02, 0.01, 0.0], results
    end

    def test_single_item_returns_its_result
      results = ConcurrentExecutor.new(max_workers: 4).map([21]) { |number| number * 2 }

      assert_equal [42], results
    end

    def test_max_workers_of_one_runs_serially
      results = ConcurrentExecutor.new(max_workers: 1).map([1, 2, 3]) { |number| number + 1 }

      assert_equal [2, 3, 4], results
    end

    def test_runs_items_concurrently_when_workers_available
      results = Gate.for(ConcurrentExecutor.new(max_workers: 3), [1, 2, 3]).results_after_started(3) { |number| number * 10 }

      assert_equal [10, 20, 30], results
    end

    def test_limits_concurrent_items_to_max_workers
      surplus_started = Gate.for(ConcurrentExecutor.new(max_workers: 2), [1, 2, 3, 4]).surplus_started_after(2) { |item| item }

      assert_equal 0, surplus_started, "no more than max_workers items should run at once"
    end

    def test_explicit_max_workers_takes_precedence_over_env
      original = ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"]
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = "1"
      results = Gate.for(ConcurrentExecutor.new(max_workers: 2), [1, 2]).results_after_started(2) { |item| item }

      assert_equal [1, 2], results
    ensure
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = original
    end

    def test_propagates_worker_exception
      error = assert_raises(RuntimeError) do
        ConcurrentExecutor.new(max_workers: 3).map([1, 2, 3]) do |number|
          raise "boom from #{number}" if number == 2

          number
        end
      end

      assert_includes error.message, "boom"
    end

    def test_propagates_thread_error_from_work_item
      error = assert_raises(ThreadError) do
        ConcurrentExecutor.new(max_workers: 2).map([1, 2]) do |number|
          raise ThreadError, "thread failed" if number == 2

          number
        end
      end

      assert_includes error.message, "thread failed"
    end
  end
end
