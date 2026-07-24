# frozen_string_literal: true

require_relative "../../test_helper"
require "digest"
require "json"
require "cleo_quality_review/checks/quality_check"
require "cleo_quality_review/options"
require "cleo_quality_review/runner"

module CleoQualityReview
  class RunnerTest < Minitest::Test
    FakeClock = Struct.new(:now, keyword_init: true)

    FakeBaseResolver = Struct.new(:sha, keyword_init: true) do
      def resolve(head: "HEAD")
        sha
      end
    end

    FakeCommandRunner = Struct.new(:calls, keyword_init: true) do
      def run(*command, env: {})
        calls << command
        case command
        when ["git", "merge-base", "origin/main", "HEAD"]
          CleoQualityReview::CommandResult.new(stdout: "base-sha\n", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        when ["git", "diff", "--name-only", "--diff-filter=ACMRT", "base-sha"]
          CleoQualityReview::CommandResult.new(stdout: "app/example.rb\n", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        when ["git", "ls-files", "--others", "--exclude-standard"]
          CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        when ["git", "diff", "base-sha", "--", "app/example.rb"]
          CleoQualityReview::CommandResult.new(stdout: "diff --git a/app/example.rb b/app/example.rb\n", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        when ["git", "ls-files", "--others", "--exclude-standard", "--", "app/example.rb"]
          CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        else
          CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        end
      end
    end

    FakeCheckRegistry = Struct.new(:received_checks, keyword_init: true) do
      def resolve(checks)
        self.received_checks = checks
        [FakeCheck]
      end
    end

    FakeCheck = Class.new(Checks::QualityCheck) do
      self.check_name = "fake"
      self.tool_name = "fake"
      self.tool_type = "custom"

      private

      def command(files)
        ["fake", *files]
      end

      def parse(_stdout, _stderr)
        [
          result(
            check: "Fake",
            message: "fake result",
            filepath: "app/example.rb",
            line: 1,
          ),
        ]
      end
    end

    OtherFakeCheck = Class.new(Checks::QualityCheck) do
      self.check_name = "other"
      self.tool_name = "other"
      self.tool_type = "custom"

      private

      def command(files)
        ["other", *files]
      end

      def parse(_stdout, _stderr)
        [
          result(
            check: "Other",
            message: "other result",
            filepath: "app/example.rb",
            line: 1,
          ),
        ]
      end
    end

    SelectableCheckRegistry = Struct.new(:received_checks, keyword_init: true) do
      CHECKS = {
        "fake" => FakeCheck,
        "other" => OtherFakeCheck,
      }.freeze

      def resolve(checks)
        self.received_checks = checks
        checks.map { |check| CHECKS.fetch(check) }
      end
    end

    def test_runs_checks_and_writes_artifacts
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        check_registry = FakeCheckRegistry.new
        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: false),
          command_runner: command_runner,
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: check_registry,
        )

        run = runner.run

        assert_completed_run(run, check_registry)
      end
    end

    def test_defaults_to_changed_mode_when_no_files_provided
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: false),
          command_runner: command_runner,
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: FakeCheckRegistry.new,
        )

        runner.run

        git_commands = command_runner.calls.select { |cmd| cmd.first == "git" }
        assert git_commands.any? { |cmd| cmd.include?("merge-base") }, "Should call git merge-base when no files provided"
      end
    end

    def test_uses_the_incremental_base_when_the_resolver_returns_a_commit
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        command_runner.define_singleton_method(:run) do |*command, env: {}|
          calls << command
          stdout = case command
          when ["git", "merge-base", "reviewed-sha", "HEAD"] then "reviewed-sha\n"
          when ["git", "diff", "--name-only", "--diff-filter=ACMRT", "reviewed-sha"] then "app/example.rb\n"
          when ["git", "diff", "reviewed-sha", "--", "app/example.rb"] then "diff --git a/app/example.rb b/app/example.rb\n"
          else ""
          end
          CleoQualityReview::CommandResult.new(stdout: stdout, stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
        end

        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: false),
          command_runner: command_runner,
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: FakeCheckRegistry.new,
          base_resolver: FakeBaseResolver.new(sha: "reviewed-sha"),
        )

        runner.run

        assert_includes command_runner.calls, ["git", "merge-base", "reviewed-sha", "HEAD"]
      end
    end

    def test_falls_back_to_the_default_base_when_the_resolver_returns_nil
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: false),
          command_runner: command_runner,
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: FakeCheckRegistry.new,
          base_resolver: FakeBaseResolver.new(sha: nil),
        )

        runner.run

        assert_includes command_runner.calls, ["git", "merge-base", "origin/main", "HEAD"]
      end
    end

    def test_exclude_removes_specified_checks
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        check_registry = FakeCheckRegistry.new
        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["all"], files: [], exclude: ["fake"], changed: false),
          command_runner: FakeCommandRunner.new(calls: []),
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: check_registry,
        )

        run = runner.run

        assert_equal [], run.checks
      end
    end

    def test_only_and_exclude_combined_exclude_takes_precedence
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        check_registry = FakeCheckRegistry.new
        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: ["fake"], changed: false),
          command_runner: FakeCommandRunner.new(calls: []),
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: check_registry,
        )

        run = runner.run

        assert_equal [], run.checks
      end
    end

    def test_changed_with_no_git_changes_returns_empty_target_files
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        command_runner.define_singleton_method(:run) do |*command, env: {}|
          calls << command
          case command
          when ["git", "merge-base", "origin/main", "HEAD"]
            CleoQualityReview::CommandResult.new(stdout: "base-sha\n", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          when ["git", "diff", "--name-only", "--diff-filter=ACMRT", "base-sha"]
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          when ["git", "ls-files", "--others", "--exclude-standard"]
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          else
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          end
        end

        runner = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: true),
          command_runner: command_runner,
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: FakeCheckRegistry.new,
        )

        run = runner.run

        assert_equal [], run.target_files
      end
    end

    def test_reuses_completed_artifacts_for_same_diff
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        options = Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: false)

        2.times do
          Runner.new(
            options: options,
            command_runner: command_runner,
            clock: FakeClock.new(now: Time.at(123)),
            check_registry: FakeCheckRegistry.new,
          ).run
        end

        fake_tool_calls = command_runner.calls.select { |command| command == ["fake", "app/example.rb"] }
        assert_equal 1, fake_tool_calls.length
      end
    end

    def test_custom_base_ref_is_included_in_non_default_review_id
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        diff = diff_content
        command_runner.define_singleton_method(:run) do |*command, env: {}|
          calls << command
          case command
          when ["git", "merge-base", "origin/feature-branch", "HEAD"]
            CleoQualityReview::CommandResult.new(stdout: "feature-base\n", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          when ["git", "diff", "--name-only", "--diff-filter=ACMRT", "feature-base"]
            CleoQualityReview::CommandResult.new(stdout: "app/example.rb\n", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          when ["git", "ls-files", "--others", "--exclude-standard"]
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          when ["git", "diff", "feature-base", "--", "app/example.rb"]
            CleoQualityReview::CommandResult.new(stdout: diff, stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          when ["git", "ls-files", "--others", "--exclude-standard", "--", "app/example.rb"]
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          else
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          end
        end

        run = Runner.new(
          options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: true, base: "origin/feature-branch"),
          command_runner: command_runner,
          clock: FakeClock.new(now: Time.at(123)),
          check_registry: FakeCheckRegistry.new,
        ).run

        assert_equal "origin/feature-branch", run.base_ref
        assert_equal expected_review_id(base_ref: "origin/feature-branch"), run.review_id
      end
    end

    def test_unresolved_changed_mode_base_ref_fails_before_artifacts_complete
      in_tmpdir do
        command_runner = FakeCommandRunner.new(calls: [])
        command_runner.define_singleton_method(:run) do |*command, env: {}|
          calls << command
          case command
          when ["git", "merge-base", "origin/missing", "HEAD"]
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "fatal\n", status: CleoQualityReviewTestHelpers::Status.new(false))
          else
            CleoQualityReview::CommandResult.new(stdout: "", stderr: "", status: CleoQualityReviewTestHelpers::Status.new(true))
          end
        end

        error = assert_raises(ArgumentError) do
          Runner.new(
            options: Options::ParseResult.new(format: "agent", checks: ["fake"], files: [], exclude: [], changed: true, base: "origin/missing"),
            command_runner: command_runner,
            clock: FakeClock.new(now: Time.at(123)),
            check_registry: FakeCheckRegistry.new,
          ).run
        end

        assert_equal "Could not resolve quality review base ref: origin/missing", error.message
        refute_path_exists "tmp/quality_checks"
      end
    end

    def test_cache_key_includes_selected_checks
      in_tmpdir do
        FileUtils.mkdir_p("app")
        File.write("app/example.rb", "# frozen_string_literal: true\n")

        command_runner = FakeCommandRunner.new(calls: [])
        fake_run = runner_for(checks: ["fake"], command_runner: command_runner, check_registry: SelectableCheckRegistry.new).run
        other_run = runner_for(checks: ["other"], command_runner: command_runner, check_registry: SelectableCheckRegistry.new).run

        assert_distinct_review_ids(fake_run, other_run)
        assert_tool_called_once(command_runner, "fake")
        assert_tool_called_once(command_runner, "other")
      end
    end

    private

    def assert_completed_run(run, check_registry)
      review_id = expected_review_id

      assert_equal 123000, run.timestamp
      assert_equal ["app/example.rb"], run.target_files
      assert_equal ["fake"], run.checks
      assert_equal ["fake"], check_registry.received_checks
      result = run.results.first
      assert_equal "fake result", result.result
      assert_equal "fake", result.tool_name
      assert_equal "custom", result.tool_type
      assert_equal review_id, run.review_id
      assert_artifacts_written(review_id)
      assert_equal "", run.artifacts.raw_check_outputs.fetch("fake")
    end

    def assert_distinct_review_ids(fake_run, other_run)
      assert_equal expected_review_id(checks: ["fake"]), fake_run.review_id
      assert_equal expected_review_id(checks: ["other"]), other_run.review_id
      refute_equal fake_run.review_id, other_run.review_id
    end

    def assert_tool_called_once(command_runner, tool)
      assert_equal 1, command_runner.calls.count { |command| command == [tool, "app/example.rb"] }
    end

    def runner_for(checks:, command_runner:, check_registry:)
      Runner.new(
        options: Options::ParseResult.new(format: "agent", checks: checks, files: [], exclude: [], changed: false),
        command_runner: command_runner,
        clock: FakeClock.new(now: Time.at(123)),
        check_registry: check_registry,
      )
    end

    def assert_artifacts_written(review_id)
      assert_equal diff_content, File.read("tmp/quality_checks/#{review_id}/changes.diff")
      assert_equal "", File.read("tmp/quality_checks/#{review_id}/custom/fake/raw_output.txt")
      assert_path_exists "tmp/quality_checks/#{review_id}/complete.json"
      assert_path_exists "tmp/quality_checks/#{review_id}/manifest.json"
      assert_path_exists "tmp/quality_checks/#{review_id}/results.json"
    end

    def expected_review_id(checks: ["fake"], diff: diff_content, base_ref: "origin/main")
      payload = { diff: diff, checks: checks.sort }
      payload[:base_ref] = base_ref unless base_ref == "origin/main"

      Digest::SHA256.hexdigest(JSON.generate(payload))
    end

    def diff_content
      "diff --git a/app/example.rb b/app/example.rb\n"
    end
  end
end
