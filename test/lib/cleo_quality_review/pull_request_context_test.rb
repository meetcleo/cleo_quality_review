# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/pull_request_context"

module CleoQualityReview
  class PullRequestContextTest < Minitest::Test
    def test_pull_request_when_the_event_is_a_pull_request_returns_true
      in_tmpdir do |dir|
        path = File.join(dir, "event.json")
        File.write(path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))

        assert_predicate PullRequestContext.new(env: { "GITHUB_EVENT_PATH" => path }), :pull_request?
      end
    end

    def test_pull_request_when_the_event_is_not_a_pull_request_returns_false
      in_tmpdir do |dir|
        path = File.join(dir, "event.json")
        File.write(path, JSON.generate({ "push" => {} }))

        refute_predicate PullRequestContext.new(env: { "GITHUB_EVENT_PATH" => path }), :pull_request?
      end
    end

    def test_pull_request_when_the_event_path_is_missing_returns_false
      refute_predicate PullRequestContext.new(env: {}), :pull_request?
    end

    def test_number_when_set_at_the_top_level_returns_it
      in_tmpdir do |dir|
        path = File.join(dir, "event.json")
        File.write(path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))

        assert_equal 42, PullRequestContext.new(env: { "GITHUB_EVENT_PATH" => path }).number
      end
    end

    def test_number_when_only_nested_under_pull_request_still_returns_it
      in_tmpdir do |dir|
        path = File.join(dir, "event.json")
        File.write(path, JSON.generate({ "pull_request" => { "number" => 7, "head" => { "sha" => "head-sha" } } }))

        assert_equal 7, PullRequestContext.new(env: { "GITHUB_EVENT_PATH" => path }).number
      end
    end

    def test_head_sha_when_inside_a_pull_request_returns_the_head_commit_sha
      in_tmpdir do |dir|
        path = File.join(dir, "event.json")
        File.write(path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))

        assert_equal "head-sha", PullRequestContext.new(env: { "GITHUB_EVENT_PATH" => path }).head_sha
      end
    end

    def test_head_sha_when_outside_a_pull_request_returns_nil
      assert_nil PullRequestContext.new(env: {}).head_sha
    end

    def test_token_when_set_returns_it
      assert_equal "secret", PullRequestContext.new(env: { "GITHUB_TOKEN" => "secret" }).token
    end

    def test_token_when_unset_returns_nil
      assert_nil PullRequestContext.new(env: {}).token
    end

    def test_repository_when_set_returns_the_owner_and_repo_slug
      assert_equal "owner/repo", PullRequestContext.new(env: { "GITHUB_REPOSITORY" => "owner/repo" }).repository
    end

    def test_repository_when_unset_returns_nil
      assert_nil PullRequestContext.new(env: {}).repository
    end

    def test_api_url_when_set_returns_the_configured_url
      assert_equal "https://api.example", PullRequestContext.new(env: { "GITHUB_API_URL" => "https://api.example" }).api_url
    end

    def test_api_url_when_unset_returns_the_default
      assert_equal "https://api.github.com", PullRequestContext.new(env: {}).api_url
    end
  end
end
