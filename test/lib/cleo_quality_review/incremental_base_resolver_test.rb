# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/command_result"
require "cleo_quality_review/incremental_base_resolver"

module CleoQualityReview
  class IncrementalBaseResolverTest < Minitest::Test
    FakeStickyComment = Struct.new(:reviewed_commit_sha)

    class RaisingStickyComment
      def reviewed_commit_sha
        raise Error, "boom"
      end
    end

    # Stubs `git merge-base --is-ancestor <sha> HEAD`, succeeding only for known ancestor SHAs.
    FakeGit = Struct.new(:ancestors, keyword_init: true) do
      def run(*command, env: {})
        _git, subcommand, flag, sha, * = command
        is_ancestor_query = [subcommand, flag] == %w[merge-base --is-ancestor]
        CleoQualityReview::CommandResult.new(
          stdout: "",
          stderr: "",
          status: CleoQualityReviewTestHelpers::Status.new(is_ancestor_query && ancestors.include?(sha)),
        )
      end
    end

    def test_resolve_when_there_is_no_pull_request_context_returns_nil
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "push" => {} }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: []),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          comment: FakeStickyComment.new("sha1"),
        )

        assert_nil resolver.resolve
      end
    end

    def test_resolve_when_there_is_no_token_returns_nil
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: []),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_REPOSITORY" => "owner/repo" },
          comment: FakeStickyComment.new("sha1"),
        )

        assert_nil resolver.resolve
      end
    end

    def test_resolve_when_disabled_by_env_toggle_returns_nil
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: %w[sha1]),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo", "CLEO_QUALITY_REVIEW_INCREMENTAL" => "0" },
          comment: FakeStickyComment.new("sha1"),
        )

        assert_nil resolver.resolve
      end
    end

    def test_resolve_when_no_sticky_comment_has_reviewed_a_commit_returns_nil
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: []),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          comment: FakeStickyComment.new(nil),
        )

        assert_nil resolver.resolve
      end
    end

    def test_resolve_when_the_reviewed_commit_is_an_ancestor_of_head_returns_it
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: %w[sha1]),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          comment: FakeStickyComment.new("sha1"),
        )

        assert_equal "sha1", resolver.resolve
      end
    end

    def test_resolve_when_the_reviewed_commit_is_not_an_ancestor_of_head_returns_nil
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: []),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          comment: FakeStickyComment.new("rewritten-sha"),
        )

        assert_nil resolver.resolve
      end
    end

    def test_resolve_when_the_lookup_raises_returns_nil_without_raising
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        resolver = IncrementalBaseResolver.new(
          command_runner: FakeGit.new(ancestors: []),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_TOKEN" => "t", "GITHUB_REPOSITORY" => "owner/repo" },
          comment: RaisingStickyComment.new,
        )

        capture_io { assert_nil resolver.resolve }
      end
    end
  end
end
