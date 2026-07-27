# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/github_client"
require "cleo_quality_review/github_review_publisher"
require "cleo_quality_review/run"
require "cleo_quality_review/run_artifacts"

module CleoQualityReview
  class GitHubReviewPublisherTest < Minitest::Test
    FakeGitHubClient = Struct.new(:requests, :get_body, keyword_init: true) do
      def get(path)
        requests << [:get, path, nil]
        GitHubClient::Response.new(status_code: 200, body: get_body || "[]")
      end

      def post(path, body)
        requests << [:post, path, body]
        GitHubClient::Response.new(status_code: 201, body: "{}")
      end
    end

    def test_skips_without_pull_request_context
      in_tmpdir do |dir|
        event_path = write_event(dir, { "push" => {} })
        publisher = GitHubReviewPublisher.new(
          run: run_with_findings,
          rendered_review: rendered_review,
          env: {
            "GITHUB_EVENT_PATH" => event_path,
            "GITHUB_REPOSITORY" => "owner/repo",
            "GITHUB_TOKEN" => "token",
          },
        )

        assert_equal "No pull_request event found; skipping PR review publication.", publisher.publish
      end
    end

    def test_skips_when_rendered_review_has_no_comments
      publisher = GitHubReviewPublisher.new(
        run: run_with_findings,
        rendered_review: JSON.generate({ body: "No issues", comments: [] }),
        env: {},
      )

      assert_equal "No PR review comments to publish.", publisher.publish
    end

    def test_publishes_review_payload
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        requests = []
        publisher = GitHubReviewPublisher.new(
          run: run_with_findings,
          rendered_review: rendered_review,
          env: {
            "GITHUB_EVENT_PATH" => event_path,
            "GITHUB_REPOSITORY" => "owner/repo",
          },
          client: FakeGitHubClient.new(requests: requests),
        )

        assert_equal "Published PR review for review ID review-id.", publisher.publish
        assert_review_requests(requests)
      end
    end

    def test_skips_when_review_already_published
      in_tmpdir do |dir|
        event_path = write_event(dir, pull_request_event)
        existing = JSON.generate([{ "body" => "<!-- cleo-quality-review:review-id -->" }])
        publisher = GitHubReviewPublisher.new(
          run: run_with_findings,
          rendered_review: rendered_review,
          env: {
            "GITHUB_EVENT_PATH" => event_path,
            "GITHUB_REPOSITORY" => "owner/repo",
          },
          client: FakeGitHubClient.new(requests: [], get_body: existing),
        )

        assert_equal "PR review already published for review ID review-id; skipping.", publisher.publish
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

    def assert_review_requests(requests)
      review_request = requests.last

      assert_equal :get, requests.first.first
      assert_equal :post, review_request.first
      assert_equal "/repos/owner/repo/pulls/42/reviews", review_request[1]
      assert_equal "head-sha", review_request[2].fetch(:commit_id)
    end

    def run_with_findings
      artifacts = RunArtifacts.new(
        review_id: "review-id",
        changes_diff: <<~DIFF,
          diff --git a/app/example.rb b/app/example.rb
          --- a/app/example.rb
          +++ b/app/example.rb
          @@ -1,1 +1,2 @@
           class Example
          +  def perform = true
        DIFF
      ).prepare!
      Run.new(
        review_id: "review-id",
        timestamp: 123,
        checks: ["reek"],
        target_files: ["app/example.rb"],
        results: [
          Result.new(tool_name: "reek", tool_type: "smell_detection", check: "DuplicateMethodCall", timestamp: 123, result: "call repeated", filepath: "app/example.rb", line: 2),
        ],
        artifacts: artifacts,
      )
    end

    def rendered_review
      JSON.generate(
        {
          body: "Review body",
          comments: [
            { path: "app/example.rb", line: 2, body: "Inline comment" },
          ],
        },
      )
    end
  end
end
