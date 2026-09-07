# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/github_client"
require "cleo_quality_review/sticky_comment"

module CleoQualityReview
  class StickyCommentTest < Minitest::Test
    FakeContext = Struct.new(:repository, :number, keyword_init: true)

    FakeGitHubClient = Struct.new(:requests, :get_body, keyword_init: true) do
      def get(path)
        requests << [:get, path, nil]
        GitHubClient::Response.new(status_code: 200, body: get_body || "[]")
      end

      def post(path, body)
        requests << [:post, path, body]
        GitHubClient::Response.new(status_code: 201, body: "{}")
      end

      def patch(path, body)
        requests << [:patch, path, body]
        GitHubClient::Response.new(status_code: 200, body: "{}")
      end
    end

    # Returns a distinct body per page number parsed from the request path.
    PaginatedGitHubClient = Struct.new(:pages, :requests, keyword_init: true) do
      def get(path)
        requests << [:get, path, nil]
        page = path[/[?&]page=(\d+)/, 1].to_i
        GitHubClient::Response.new(status_code: 200, body: pages[page] || "[]")
      end
    end

    def test_exists_when_no_comment_carries_the_marker_returns_false
      client = FakeGitHubClient.new(requests: [], get_body: "[]")
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      refute_predicate comment, :exists?
    end

    def test_exists_when_a_bot_comment_carries_the_marker_returns_true
      existing = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->" }])
      client = FakeGitHubClient.new(requests: [], get_body: existing)
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_predicate comment, :exists?
    end

    def test_exists_when_the_marker_is_forged_on_a_human_comment_returns_false
      forged = JSON.generate([{ "id" => 99, "user" => { "type" => "User" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->" }])
      client = FakeGitHubClient.new(requests: [], get_body: forged)
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      refute_predicate comment, :exists?
    end

    def test_reviewed_commit_sha_when_a_marked_comment_exists_returns_the_parsed_sha
      existing = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->\n\nFindings" }])
      client = FakeGitHubClient.new(requests: [], get_body: existing)
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_equal "old-sha", comment.reviewed_commit_sha
    end

    def test_reviewed_commit_sha_when_no_comment_exists_returns_nil
      client = FakeGitHubClient.new(requests: [], get_body: "[]")
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_nil comment.reviewed_commit_sha
    end

    def test_reviewed_commit_sha_when_the_marker_has_no_extractable_commit_returns_nil
      malformed = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: -->" }])
      client = FakeGitHubClient.new(requests: [], get_body: malformed)
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_nil comment.reviewed_commit_sha
    end

    def test_exists_when_checking_requests_the_expected_comments_path
      client = FakeGitHubClient.new(requests: [], get_body: "[]")
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      comment.exists?

      assert_equal "/repos/owner/repo/issues/42/comments?per_page=100&page=1", client.requests.first[1]
    end

    def test_save_when_none_exists_creates_a_comment
      client = FakeGitHubClient.new(requests: [], get_body: "[]")
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_equal :created, comment.save!("New findings")
      create_request = client.requests.last
      assert_equal :post, create_request.first
      assert_equal "/repos/owner/repo/issues/42/comments", create_request[1]
      assert_equal({ body: "New findings" }, create_request[2])
    end

    def test_save_when_one_already_exists_updates_it_in_place
      existing = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->" }])
      client = FakeGitHubClient.new(requests: [], get_body: existing)
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_equal :updated, comment.save!("Updated findings")
      update_request = client.requests.last
      assert_equal :patch, update_request.first
      assert_equal "/repos/owner/repo/issues/comments/99", update_request[1]
      assert_equal({ body: "Updated findings" }, update_request[2])
    end

    def test_save_when_the_creation_request_fails_raises
      client = FakeGitHubClient.new(requests: [], get_body: "[]")
      client.define_singleton_method(:post) { |*| GitHubClient::Response.new(status_code: 500, body: "boom") }
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_raises(Error) { comment.save!("New findings") }
    end

    def test_exists_when_the_lookup_request_fails_raises
      client = FakeGitHubClient.new(requests: [], get_body: "boom")
      client.define_singleton_method(:get) { |*| GitHubClient::Response.new(status_code: 500, body: "boom") }
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_raises(Error) { comment.exists? }
    end

    def test_reviewed_commit_sha_when_the_marked_comment_is_beyond_the_first_page_still_finds_it
      full_page = JSON.generate(Array.new(StickyComment::COMMENTS_PER_PAGE) { { "id" => 1, "user" => { "type" => "User" }, "body" => "chatter" } })
      late_page = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: commit=sha-late -->" }])
      client = PaginatedGitHubClient.new(pages: { 1 => full_page, 2 => late_page }, requests: [])
      comment = StickyComment.new(client: client, context: FakeContext.new(repository: "owner/repo", number: 42))

      assert_equal "sha-late", comment.reviewed_commit_sha
    end
  end
end
