# frozen_string_literal: true

require_relative "../../test_helper"
require "etc"
require "timeout"
require "cleo_quality_review/concurrent_executor"

module CleoQualityReview
  class ConcurrentExecutorTest < Minitest::Test
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
      started = Thread::Queue.new
      release = Thread::Queue.new
      results = nil

      runner = Thread.new do
        results = ConcurrentExecutor.new(max_workers: 3).map([1, 2, 3]) do |item|
          started << item
          release.pop
          item * 10
        end
      end

      Timeout.timeout(5) { 3.times { started.pop } }
      3.times { release << :go }
      runner.join

      assert_equal [10, 20, 30], results
    end

    def test_caps_concurrency_at_max_workers
      started = Thread::Queue.new
      release = Thread::Queue.new

      runner = Thread.new do
        ConcurrentExecutor.new(max_workers: 2).map([1, 2, 3, 4]) do |item|
          started << item
          release.pop
          item
        end
      end

      Timeout.timeout(5) { 2.times { started.pop } }
      sleep(0.05) # allow any (incorrect) surplus workers to start

      assert_equal 0, started.size, "no more than max_workers items should run at once"
    ensure
      4.times { release << :go }
      runner&.join
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
