# frozen_string_literal: true

require_relative "../../test_helper"
require "etc"
require "timeout"
require "cleo_quality_review/concurrent_executor"

module CleoQualityReview
  class ConcurrentExecutorTest < Minitest::Test
    # Coordinates a concurrent run so a test can observe how many items run at
    # once: each mapped item reports that it started, then blocks until released.
    Gate = Struct.new(:started, :release) do
      def self.open
        new(Thread::Queue.new, Thread::Queue.new)
      end

      # Run +executor.map+ on a background thread, gating each item on this Gate.
      # @return [Thread] whose #value is the ordered map result
      def run(executor, items, &block)
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
    end

    def test_returns_empty_array_for_empty_input
      assert_equal [], ConcurrentExecutor.new(max_workers: 4).map([]) { |item| item }
    end

    def test_preserves_input_order
      results = ConcurrentExecutor.new(max_workers: 4).map([1, 2, 3, 4, 5]) { |n| n * n }

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
      results = ConcurrentExecutor.new(max_workers: 4).map([21]) { |n| n * 2 }

      assert_equal [42], results
    end

    def test_max_workers_of_one_runs_serially
      results = ConcurrentExecutor.new(max_workers: 1).map([1, 2, 3]) { |n| n + 1 }

      assert_equal [2, 3, 4], results
    end

    def test_runs_items_concurrently_when_workers_available
      gate = Gate.open
      runner = gate.run(ConcurrentExecutor.new(max_workers: 3), [1, 2, 3]) { |n| n * 10 }
      gate.await_started(3)
      gate.release_all(3)

      assert_equal [10, 20, 30], runner.value
    end

    def test_caps_concurrency_at_max_workers
      gate = Gate.open
      runner = gate.run(ConcurrentExecutor.new(max_workers: 2), [1, 2, 3, 4]) { |item| item }
      gate.await_started(2)
      sleep(0.05) # let any surplus workers (a broken cap) start and signal

      assert_equal 0, gate.started.size, "no more than max_workers items should run at once"
    ensure
      gate.release_all(4)
      runner&.value
    end

    def test_propagates_worker_exception
      error = assert_raises(RuntimeError) do
        ConcurrentExecutor.new(max_workers: 3).map([1, 2, 3]) do |n|
          raise "boom from #{n}" if n == 2

          n
        end
      end

      assert_includes error.message, "boom"
    end

    def test_resolve_prefers_explicit_value_over_env
      original = ENV[ConcurrentExecutor::ENV_VAR]
      ENV[ConcurrentExecutor::ENV_VAR] = "7"

      assert_equal 3, ConcurrentExecutor.resolve_max_workers(3)
    ensure
      ENV[ConcurrentExecutor::ENV_VAR] = original
    end

    def test_resolve_uses_env_var_when_no_explicit_value
      original = ENV[ConcurrentExecutor::ENV_VAR]
      ENV[ConcurrentExecutor::ENV_VAR] = "7"

      assert_equal 7, ConcurrentExecutor.resolve_max_workers
    ensure
      ENV[ConcurrentExecutor::ENV_VAR] = original
    end

    def test_resolve_ignores_blank_env_var
      original = ENV[ConcurrentExecutor::ENV_VAR]
      ENV[ConcurrentExecutor::ENV_VAR] = "   "

      assert_equal Etc.nprocessors, ConcurrentExecutor.resolve_max_workers
    ensure
      ENV[ConcurrentExecutor::ENV_VAR] = original
    end

    def test_resolve_falls_back_to_processor_count
      original = ENV[ConcurrentExecutor::ENV_VAR]
      ENV.delete(ConcurrentExecutor::ENV_VAR)

      assert_equal Etc.nprocessors, ConcurrentExecutor.resolve_max_workers
    ensure
      ENV[ConcurrentExecutor::ENV_VAR] = original
    end

    def test_resolve_clamps_zero_to_one
      assert_equal 1, ConcurrentExecutor.resolve_max_workers(0)
    end

    def test_resolve_clamps_negative_to_one
      assert_equal 1, ConcurrentExecutor.resolve_max_workers(-4)
    end
  end
end
