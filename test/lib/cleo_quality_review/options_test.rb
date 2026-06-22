# frozen_string_literal: true

require_relative "../../test_helper"
require "cleo_quality_review/options"

module CleoQualityReview
  class OptionsTest < Minitest::Test
    def test_defaults_to_human_format_and_all_checks
      options = Options.parse([])

      assert_equal "human", options.format
      assert_equal ["all"], options.checks
      assert_equal [], options.files
    end

    def test_parses_repeated_comma_separated_checks_and_files
      options = Options.parse(
        [
          "--format",
          "agent",
          "--checks",
          "reek,flog",
          "--checks",
          "fasterer",
          "--files",
          "app/a.rb,README.md",
          "--files",
          "app/b.rb",
        ],
      )

      assert_equal "agent", options.format
      assert_equal %w[reek flog fasterer], options.checks
      assert_equal ["app/a.rb", "README.md", "app/b.rb"], options.files
    end

    def test_rejects_unknown_format
      error = assert_raises(OptionParser::InvalidArgument) do
        Options.parse(["--format", "xml"])
      end

      assert_includes error.message, "invalid argument"
    end

    def test_accepts_pr_review_format
      options = Options.parse(["--format", "pr_review"])

      assert_equal "pr_review", options.format
    end

    def test_parses_only_as_alias_for_checks
      options = Options.parse(["--only", "reek,flog"])

      assert_equal %w[reek flog], options.checks
    end

    def test_parses_exclude_flag
      options = Options.parse(["--exclude", "flog,fasterer"])

      assert_equal %w[flog fasterer], options.exclude
    end

    def test_parses_repeated_exclude_flags
      options = Options.parse(["--exclude", "flog", "--exclude", "fasterer"])

      assert_equal %w[flog fasterer], options.exclude
    end

    def test_parses_changed_flag
      options = Options.parse(["--changed"])

      assert_predicate options, :changed
    end

    def test_parses_base_ref
      options = Options.parse(["--base", "origin/feature-branch"])

      assert_equal "origin/feature-branch", options.base
    end

    def test_changed_defaults_to_false
      options = Options.parse([])

      refute_predicate options, :changed
    end

    def test_base_defaults_to_origin_main
      options = Options.parse([])

      assert_equal "origin/main", options.base
    end

    def test_exclude_defaults_to_empty_array
      options = Options.parse([])

      assert_equal [], options.exclude
    end

    def test_positional_arguments_are_treated_as_files
      options = Options.parse(["lib/foo.rb", "lib/bar.rb"])

      assert_equal ["lib/foo.rb", "lib/bar.rb"], options.files
    end

    def test_positional_arguments_combine_with_files_flag
      options = Options.parse(["--files", "lib/a.rb", "lib/b.rb", "lib/c.rb"])

      assert_equal ["lib/a.rb", "lib/b.rb", "lib/c.rb"], options.files
    end

    def test_parses_log_flag
      options = Options.parse(["--log"])

      assert_predicate options, :log
    end

    def test_parses_review_id
      options = Options.parse(["--review-id", "abc123"])

      assert_equal "abc123", options.review_id
    end

    def test_parses_review_file
      options = Options.parse(["--review-file", "tmp/review.json"])

      assert_equal "tmp/review.json", options.review_file
    end

    def test_log_defaults_to_false
      options = Options.parse([])

      refute_predicate options, :log
    end

    def test_parses_jobs_flag
      options = Options.parse(["--jobs", "4"])

      assert_equal 4, options.jobs
    end

    def test_parses_jobs_short_flag
      options = Options.parse(["-j", "2"])

      assert_equal 2, options.jobs
    end

    def test_jobs_defaults_to_nil
      options = Options.parse([])

      assert_nil options.jobs
    end
  end
end
