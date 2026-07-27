# frozen_string_literal: true

require_relative "../../test_helper"
require "etc"
require "cleo_quality_review/configuration"

module CleoQualityReview
  class ConfigurationTest < Minitest::Test
    def test_loads_gem_default_config
      in_tmpdir do
        config = Configuration.load

        assert config.target_file?("app/models/user.rb")
        refute config.target_file?("README.md")
        refute config.target_file?("vendor/cleo_quality_review/lib/example.rb")
      end
    end

    def test_local_config_merges_with_default_config
      in_tmpdir do
        File.write(
          ".cleo_quality_review.yaml",
          <<~YAML,
            AllTools:
              Include:
                - "**/*.rake"
              Exclude:
                - "app/generated/**/*"
          YAML
        )

        config = Configuration.load

        assert config.target_file?("app/models/user.rb")
        assert config.target_file?("lib/tasks/import.rake")
        refute config.target_file?("app/generated/user.rb")
      end
    end

    def test_local_config_can_inherit_from_relative_config
      in_tmpdir do
        FileUtils.mkdir_p("config")
        File.write(
          "config/user.yml",
          <<~YAML,
            AllTools:
              Exclude:
                - "app/private/**/*"
          YAML
        )
        File.write(
          ".cleo_quality_review.yaml",
          <<~YAML,
            inherit_from: config/user.yml

            AllTools:
              Include:
                - "**/*.rake"
          YAML
        )

        config = Configuration.load

        assert config.target_file?("app/models/user.rb")
        assert config.target_file?("lib/tasks/import.rake")
        refute config.target_file?("app/private/token.rb")
      end
    end

    def test_inherit_from_expands_user_home_paths
      original_home = ENV.fetch("HOME", nil)

      in_tmpdir do |dir|
        home = File.join(dir, "home")
        FileUtils.mkdir_p(File.join(home, ".config"))
        File.write(
          File.join(home, ".config", "cleo_quality_review.yml"),
          <<~YAML,
            AllTools:
              Exclude:
                - "app/local/**/*"
          YAML
        )
        File.write(
          ".cleo_quality_review.yaml",
          <<~YAML,
            inherit_from: ~/.config/cleo_quality_review.yml
          YAML
        )

        ENV["HOME"] = home
        config = Configuration.load

        refute config.target_file?("app/local/user.rb")
      end
    ensure
      ENV["HOME"] = original_home
    end

    def test_invalid_config_file_fails
      in_tmpdir do
        File.write(".cleo_quality_review.yaml", "- not-a-mapping\n")

        error = assert_raises(ArgumentError) { Configuration.load }

        assert_includes error.message, "Config file must contain a YAML mapping"
      end
    end

    def test_missing_inherited_config_fails
      in_tmpdir do
        File.write(".cleo_quality_review.yaml", "inherit_from: missing.yml\n")

        error = assert_raises(ArgumentError) { Configuration.load }

        assert_includes error.message, "Config file not found"
      end
    end

    def test_max_concurrency_uses_env_var_when_set
      original = ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"]
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = "7"

      assert_equal 7, Configuration.max_concurrency
    ensure
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = original
    end

    def test_max_concurrency_ignores_blank_env_var
      original = ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"]
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = "   "

      assert_equal Etc.nprocessors, Configuration.max_concurrency
    ensure
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = original
    end

    def test_max_concurrency_falls_back_to_processor_count
      original = ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"]
      ENV.delete("CLEO_QUALITY_REVIEW_MAX_CONCURRENCY")

      assert_equal Etc.nprocessors, Configuration.max_concurrency
    ensure
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = original
    end

    def test_max_concurrency_fails_for_non_integer_env_var
      original = ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"]
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = "many"

      assert_raises(ArgumentError) { Configuration.max_concurrency }
    ensure
      ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"] = original
    end

    def test_max_concurrency_limit_clamps_zero_to_one
      assert_equal 1, Configuration.max_concurrency_limit(0)
    end

    def test_max_concurrency_limit_clamps_negative_to_one
      assert_equal 1, Configuration.max_concurrency_limit(-4)
    end
  end
end
