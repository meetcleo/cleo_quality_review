# frozen_string_literal: true

require_relative "../../test_helper"
require "digest"
require "cleo_quality_review/changes_diff"

module CleoQualityReview
  class ChangesDiffTest < Minitest::Test
    Runner = Struct.new(:calls, keyword_init: true) do
      def run(*command, env: {})
        calls << command
        case command
        when ["git", "merge-base", "origin/main", "HEAD"]
          command_result(stdout: "base-sha\n")
        when ["git", "diff", "base-sha", "--", "app/example.rb"]
          command_result(stdout: "diff content")
        when ["git", "ls-files", "--others", "--exclude-standard", "--", "app/example.rb"]
          command_result(stdout: "")
        else
          command_result(stdout: "")
        end
      end

      private

      def command_result(stdout:)
        CleoQualityReview::CommandResult.new(
          stdout: stdout,
          stderr: "",
          status: CleoQualityReviewTestHelpers::Status.new(true),
        )
      end
    end

    def test_captures_diff_and_review_id
      changes = ChangesDiff.new(target_files: ["app/example.rb"], command_runner: Runner.new(calls: []))

      assert_equal "diff content", changes.to_s
      assert_equal Digest::SHA256.hexdigest("diff content"), changes.review_id
    end

    def test_empty_target_files_produce_empty_diff_without_running_git
      command_runner = Runner.new(calls: [])
      changes = ChangesDiff.new(target_files: [], command_runner: command_runner)

      assert_equal "", changes.to_s
      assert_empty command_runner.calls
    end

    def test_empty_target_files_review_id_is_hash_of_empty_diff
      changes = ChangesDiff.new(target_files: [], command_runner: Runner.new(calls: []))

      assert_equal Digest::SHA256.hexdigest(""), changes.review_id
    end

    def test_uses_configured_base_ref_when_capturing_diff
      command_runner = Runner.new(calls: [])
      result = method(:command_result)
      command_runner.define_singleton_method(:run) do |*command, env: {}|
        calls << command
        case command
        when ["git", "merge-base", "origin/feature-branch", "HEAD"]
          result.call(stdout: "feature-base\n")
        when ["git", "diff", "feature-base", "--", "app/example.rb"]
          result.call(stdout: "feature diff")
        when ["git", "ls-files", "--others", "--exclude-standard", "--", "app/example.rb"]
          result.call(stdout: "")
        else
          result.call(stdout: "")
        end
      end

      changes = ChangesDiff.new(
        target_files: ["app/example.rb"],
        command_runner: command_runner,
        base_ref: "origin/feature-branch",
      )

      assert_equal "feature diff", changes.to_s
    end

    def test_strict_base_resolution_raises_for_unresolved_base_ref
      command_runner = Runner.new(calls: [])
      result = method(:command_result)
      command_runner.define_singleton_method(:run) do |*command, env: {}|
        calls << command
        case command
        when ["git", "merge-base", "origin/missing", "HEAD"]
          result.call(stderr: "fatal\n", success: false)
        else
          result.call(stdout: "")
        end
      end

      changes = ChangesDiff.new(
        target_files: ["app/example.rb"],
        command_runner: command_runner,
        base_ref: "origin/missing",
        strict_base: true,
      )

      error = assert_raises(ArgumentError) { changes.to_s }

      assert_equal "Could not resolve quality review base ref: origin/missing", error.message
    end

    def test_non_strict_base_resolution_falls_back_to_ref
      command_runner = Runner.new(calls: [])
      result = method(:command_result)
      command_runner.define_singleton_method(:run) do |*command, env: {}|
        calls << command
        case command
        when ["git", "merge-base", "origin/missing", "HEAD"]
          result.call(stderr: "fatal\n", success: false)
        when ["git", "diff", "origin/missing", "--", "app/example.rb"]
          result.call(stdout: "fallback diff")
        when ["git", "ls-files", "--others", "--exclude-standard", "--", "app/example.rb"]
          result.call(stdout: "")
        else
          result.call(stdout: "")
        end
      end

      changes = ChangesDiff.new(
        target_files: ["app/example.rb"],
        command_runner: command_runner,
        base_ref: "origin/missing",
        strict_base: false,
      )

      assert_equal "fallback diff", changes.to_s
    end
  end
end
