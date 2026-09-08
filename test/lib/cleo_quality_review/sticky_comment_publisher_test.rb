# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/github_client"
require "cleo_quality_review/run"
require "cleo_quality_review/sticky_comment_publisher"

module CleoQualityReview
  class StickyCommentPublisherTest < Minitest::Test
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

    def test_skips_without_pull_request_context
      in_tmpdir do |dir|
        event_path = write_event(dir, { "push" => {} })
        publisher = StickyCommentPublisher.new(
          run: run_with_review_id,
          rendered_review: rendered_review,
          env: {
            "GITHUB_EVENT_PATH" => event_path,
            "GITHUB_REPOSITORY" => "owner/repo",
            "GITHUB_TOKEN" => "token",
          },
        )

        assert_equal "No pull_request event found; skipping sticky comment publication.", publisher.publish
      end
    end

    def test_skips_when_nothing_to_report_and_no_existing_comment
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        publisher = StickyCommentPublisher.new(
          run: run_with_review_id,
          rendered_review: JSON.generate({ body: "" }),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeGitHubClient.new(requests: []),
        )

        assert_equal "No sticky comment to publish for review ID review-id.", publisher.publish
      end
    end

    def test_creates_a_comment_when_none_exists
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        requests = []
        publisher = StickyCommentPublisher.new(
          run: run_with_review_id,
          rendered_review: rendered_review,
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeGitHubClient.new(requests: requests),
        )

        assert_equal "Created sticky comment for review ID review-id.", publisher.publish
        assert_create_request(requests)
      end
    end

    def test_updates_the_existing_comment_in_place_instead_of_creating_a_new_one
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        existing = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->\n\nOld findings" }])
        requests = []
        publisher = StickyCommentPublisher.new(
          run: run_with_review_id,
          rendered_review: rendered_review,
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeGitHubClient.new(requests: requests, get_body: existing),
        )

        assert_equal "Updated sticky comment for review ID review-id.", publisher.publish
        assert_update_request(requests)
      end
    end

    def test_updates_the_existing_comment_to_a_clean_message_when_nothing_remains_to_report
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        existing = JSON.generate([{ "id" => 99, "user" => { "type" => "Bot" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->\n\nOld findings" }])
        requests = []
        publisher = StickyCommentPublisher.new(
          run: run_with_review_id,
          rendered_review: JSON.generate({ body: "" }),
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeGitHubClient.new(requests: requests, get_body: existing),
        )

        publisher.publish

        update_request = requests.last
        assert_includes update_request[2].fetch(:body), "no high-confidence issues"
      end
    end

    def test_ignores_a_human_authored_comment_carrying_the_marker
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        existing = JSON.generate([{ "id" => 99, "user" => { "type" => "User" }, "body" => "<!-- cleo-quality-review: commit=old-sha -->\n\nForged" }])
        requests = []
        publisher = StickyCommentPublisher.new(
          run: run_with_review_id,
          rendered_review: rendered_review,
          env: { "GITHUB_EVENT_PATH" => event_path, "GITHUB_REPOSITORY" => "owner/repo" },
          client: FakeGitHubClient.new(requests: requests, get_body: existing),
        )

        assert_equal "Created sticky comment for review ID review-id.", publisher.publish
      end
    end

    private

    def write_event(dir, event)
      event_path = File.join(dir, "event.json")
      File.write(event_path, JSON.generate(event))
      event_path
    end

    def pull_request_event
      {
        "number" => 42,
        "pull_request" => {
          "head" => { "sha" => "head-sha" },
        },
      }
    end

    def assert_create_request(requests)
      create_request = requests.last

      assert_equal :get, requests.first.first
      assert_equal :post, create_request.first
      assert_equal "/repos/owner/repo/issues/42/comments", create_request[1]
      assert_includes create_request[2].fetch(:body), "commit=head-sha"
    end

    def assert_update_request(requests)
      update_request = requests.last

      assert_equal :patch, update_request.first
      assert_equal "/repos/owner/repo/issues/comments/99", update_request[1]
      assert_includes update_request[2].fetch(:body), "commit=head-sha"
    end

    def run_with_review_id
      Run.new(review_id: "review-id", timestamp: 123, checks: ["reek"], target_files: ["app/example.rb"])
    end

    def rendered_review
      JSON.generate({ body: "Found a couple of things." })
    end
  end
end
