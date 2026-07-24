# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/command_result"
require "cleo_quality_review/github_client"
require "cleo_quality_review/incremental_base_resolver"

module CleoQualityReview
  class IncrementalBaseResolverTest < Minitest::Test
    FakeReviewsClient = Struct.new(:reviews_json, :status_code, :requested_paths, keyword_init: true) do
      def get(path)
        requested_paths << path
        GitHubClient::Response.new(status_code: status_code || 200, body: reviews_json || "[]")
      end
    end

    FakeGit = Struct.new(:ancestors, :calls, keyword_init: true) do
      def run(*command, env: {})
        calls << command
        CleoQualityReview::CommandResult.new(
          stdout: "",
          stderr: "",
          status: CleoQualityReviewTestHelpers::Status.new(ancestor?(command)),
        )
      end

      def ancestor?(command)
        command.first(3) == ["git", "merge-base", "--is-ancestor"] && ancestors.include?(command[3])
      end
    end

    def test_returns_nil_without_a_pull_request_context
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: { "GITHUB_EVENT_PATH" => write_event(dir, { "push" => {} }), "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeReviewsClient.new(requested_paths: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_without_a_token
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: { "GITHUB_EVENT_PATH" => write_event(dir, pull_request_event), "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeReviewsClient.new(requested_paths: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_when_disabled_by_env_toggle
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir).merge("CLEO_QUALITY_REVIEW_INCREMENTAL" => "0"),
          client: FakeReviewsClient.new(reviews_json: reviews_json, requested_paths: []),
          git: FakeGit.new(ancestors: %w[sha2], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_when_no_cleo_quality_review_exists
      in_tmpdir do |dir|
        only_other_reviews = JSON.generate([{ "body" => "LGTM", "commit_id" => "human-sha" }])
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeReviewsClient.new(reviews_json: only_other_reviews, requested_paths: []),
          git: FakeGit.new(ancestors: %w[human-sha], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_the_newest_reviewed_commit_that_is_an_ancestor
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeReviewsClient.new(reviews_json: reviews_json, requested_paths: []),
          git: FakeGit.new(ancestors: %w[sha1 sha2], calls: []),
        )

        assert_equal "sha2", resolver.resolve
      end
    end

    def test_skips_a_rewritten_newer_commit_and_falls_back_to_the_older_ancestor
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeReviewsClient.new(reviews_json: reviews_json, requested_paths: []),
          git: FakeGit.new(ancestors: %w[sha1], calls: []),
        )

        assert_equal "sha1", resolver.resolve
      end
    end

    def test_returns_nil_when_no_reviewed_commit_survives_in_history
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeReviewsClient.new(reviews_json: reviews_json, requested_paths: []),
          git: FakeGit.new(ancestors: [], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_ignores_reviews_without_a_commit_id
      in_tmpdir do |dir|
        commitless = JSON.generate([{ "body" => "<!-- cleo-quality-review:x -->", "commit_id" => nil, "submitted_at" => "2026-07-01T09:00:00Z" }])
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeReviewsClient.new(reviews_json: commitless, requested_paths: []),
          git: FakeGit.new(ancestors: %w[anything], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_and_does_not_raise_when_the_lookup_fails
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeReviewsClient.new(status_code: 500, reviews_json: "boom", requested_paths: []),
          git: FakeGit.new(ancestors: [], calls: []),
        )

        capture_io { assert_nil resolver.resolve }
      end
    end

    def test_requests_reviews_for_the_pull_request
      in_tmpdir do |dir|
        client = FakeReviewsClient.new(reviews_json: reviews_json, requested_paths: [])
        build_resolver(env: base_env(dir), client: client, git: FakeGit.new(ancestors: %w[sha2], calls: [])).resolve

        assert_equal "/repos/owner/repo/pulls/42/reviews?per_page=100", client.requested_paths.first
      end
    end

    private

    def build_resolver(env:, client:, git: nil)
      IncrementalBaseResolver.new(
        command_runner: git || FakeGit.new(ancestors: [], calls: []),
        env: env,
        client: client,
      )
    end

    def base_env(dir)
      {
        "GITHUB_EVENT_PATH" => write_event(dir, pull_request_event),
        "GITHUB_TOKEN" => "t",
        "GITHUB_REPOSITORY" => "owner/repo",
      }
    end

    def pull_request_event
      { "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }
    end

    def write_event(dir, event)
      path = File.join(dir, "event.json")
      File.write(path, JSON.generate(event))
      path
    end

    def reviews_json
      JSON.generate(
        [
          { "body" => "<!-- cleo-quality-review:aaa -->", "commit_id" => "sha1", "submitted_at" => "2026-07-01T10:00:00Z" },
          { "body" => "Looks good to me", "commit_id" => "human-sha", "submitted_at" => "2026-07-01T11:00:00Z" },
          { "body" => "<!-- cleo-quality-review:bbb -->", "commit_id" => "sha2", "submitted_at" => "2026-07-01T12:00:00Z" },
        ],
      )
    end
  end
end
