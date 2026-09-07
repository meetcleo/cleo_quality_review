# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/command_result"
require "cleo_quality_review/github_client"
require "cleo_quality_review/incremental_base_resolver"

module CleoQualityReview
  class IncrementalBaseResolverTest < Minitest::Test
    FakeCommentsClient = Struct.new(:comments_json, :status_code, :requested_paths, keyword_init: true) do
      def get(path)
        requested_paths << path
        GitHubClient::Response.new(status_code: status_code || 200, body: comments_json || "[]")
      end
    end

    # Returns a distinct body per page number parsed from the request path.
    PaginatedCommentsClient = Struct.new(:pages, :requested_paths, keyword_init: true) do
      def get(path)
        requested_paths << path
        page = path[/[?&]page=(\d+)/, 1].to_i
        GitHubClient::Response.new(status_code: 200, body: pages[page] || "[]")
      end
    end

    # Stubs `git merge-base --is-ancestor <sha> HEAD`, succeeding only for known ancestor SHAs.
    FakeGit = Struct.new(:ancestors, :calls, keyword_init: true) do
      def run(*command, env: {})
        calls << command
        _git, subcommand, flag, sha, * = command
        is_ancestor_query = [subcommand, flag] == %w[merge-base --is-ancestor]
        CleoQualityReview::CommandResult.new(
          stdout: "",
          stderr: "",
          status: CleoQualityReviewTestHelpers::Status.new(is_ancestor_query && ancestors.include?(sha)),
        )
      end
    end

    def test_returns_nil_without_a_pull_request_context
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: { "GITHUB_EVENT_PATH" => write_event(dir, { "push" => {} }), "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeCommentsClient.new(requested_paths: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_without_a_token
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: { "GITHUB_EVENT_PATH" => write_event(dir, pull_request_event), "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeCommentsClient.new(requested_paths: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_when_disabled_by_env_toggle
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir).merge("CLEO_QUALITY_REVIEW_INCREMENTAL" => "0"),
          client: FakeCommentsClient.new(comments_json: sticky_comment_json("sha1"), requested_paths: []),
          git: FakeGit.new(ancestors: %w[sha1], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_when_no_sticky_comment_exists
      in_tmpdir do |dir|
        only_other_comments = JSON.generate([{ "body" => "LGTM", "user" => { "type" => "User" } }])
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeCommentsClient.new(comments_json: only_other_comments, requested_paths: []),
          git: FakeGit.new(ancestors: %w[human-sha], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_the_reviewed_commit_when_it_is_an_ancestor
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeCommentsClient.new(comments_json: sticky_comment_json("sha1"), requested_paths: []),
          git: FakeGit.new(ancestors: %w[sha1], calls: []),
        )

        assert_equal "sha1", resolver.resolve
      end
    end

    def test_returns_nil_when_the_reviewed_commit_is_not_an_ancestor
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeCommentsClient.new(comments_json: sticky_comment_json("rewritten-sha"), requested_paths: []),
          git: FakeGit.new(ancestors: [], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_ignores_a_comment_whose_marker_has_no_extractable_commit
      in_tmpdir do |dir|
        malformed = JSON.generate([{ "body" => "<!-- cleo-quality-review: -->", "user" => { "type" => "Bot" } }])
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeCommentsClient.new(comments_json: malformed, requested_paths: []),
          git: FakeGit.new(ancestors: %w[anything], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_returns_nil_and_does_not_raise_when_the_lookup_fails
      in_tmpdir do |dir|
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeCommentsClient.new(status_code: 500, comments_json: "boom", requested_paths: []),
          git: FakeGit.new(ancestors: [], calls: []),
        )

        capture_io { assert_nil resolver.resolve }
      end
    end

    def test_requests_comments_for_the_pull_request
      in_tmpdir do |dir|
        client = FakeCommentsClient.new(comments_json: sticky_comment_json("sha1"), requested_paths: [])
        build_resolver(env: base_env(dir), client: client, git: FakeGit.new(ancestors: %w[sha1], calls: [])).resolve

        assert_equal "/repos/owner/repo/issues/42/comments?per_page=100&page=1", client.requested_paths.first
      end
    end

    def test_ignores_a_forged_marker_from_a_non_bot_comment
      in_tmpdir do |dir|
        forged = JSON.generate([{ "body" => "<!-- cleo-quality-review: commit=forged-sha -->", "user" => { "type" => "User" } }])
        resolver = build_resolver(
          env: base_env(dir),
          client: FakeCommentsClient.new(comments_json: forged, requested_paths: []),
          git: FakeGit.new(ancestors: %w[forged-sha], calls: []),
        )

        assert_nil resolver.resolve
      end
    end

    def test_follows_pagination_to_find_the_sticky_comment_beyond_the_first_page
      in_tmpdir do |dir|
        pages = { 1 => full_page_of_other_comments, 2 => sticky_comment_json("sha-late") }
        resolver = build_resolver(
          env: base_env(dir),
          client: PaginatedCommentsClient.new(pages: pages, requested_paths: []),
          git: FakeGit.new(ancestors: %w[sha-late], calls: []),
        )

        assert_equal "sha-late", resolver.resolve
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

    def sticky_comment_json(commit_sha)
      JSON.generate(
        [{ "body" => "<!-- cleo-quality-review: commit=#{commit_sha} -->\n\nSome findings", "user" => { "type" => "Bot" } }],
      )
    end

    def full_page_of_other_comments
      JSON.generate(Array.new(IncrementalBaseResolver::COMMENTS_PER_PAGE) { { "body" => "chatter", "user" => { "type" => "User" } } })
    end
  end
end
