# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/github_review_builder"
require "cleo_quality_review/run"
require "cleo_quality_review/run_artifacts"

module CleoQualityReview
  class GitHubReviewBuilderTest < Minitest::Test
    def test_builds_inline_comments_for_findings_on_diff_lines
      in_tmpdir do
        payload = GitHubReviewBuilder.new(
          run: run_with_findings,
          rendered_review: rendered_review,
        ).payload(commit_id: "head-sha")

        assert_inline_review_payload(payload)
      end
    end

    def test_blank_rendered_review_is_treated_as_empty
      in_tmpdir do
        builder = GitHubReviewBuilder.new(run: run_with_findings, rendered_review: "")

        assert_predicate builder, :empty?
      end
    end

    private

    def assert_inline_review_payload(payload)
      comments = payload.fetch(:comments)
      comment = comments.first
      body = payload.fetch(:body)

      assert_equal "COMMENT", payload.fetch(:event)
      assert_equal "head-sha", payload.fetch(:commit_id)
      assert_includes body, "cleo-quality-review:review-id"
      assert_includes body, "Review body"
      assert_equal 1, comments.length
      assert_equal "app/example.rb", comment.fetch(:path)
      assert_equal 2, comment.fetch(:line)
    end

    def run_with_findings
      Run.new(
        review_id: "review-id",
        timestamp: 123,
        checks: ["reek"],
        target_files: ["app/example.rb"],
        results: results,
        artifacts: artifacts,
      )
    end

    def artifacts
      RunArtifacts.new(
        review_id: "review-id",
        changes_diff: <<~DIFF,
          diff --git a/app/example.rb b/app/example.rb
          --- a/app/example.rb
          +++ b/app/example.rb
          @@ -1,2 +1,2 @@
           class Example
          +  def perform = true
        DIFF
      ).prepare!
    end

    def results
      [
        Result.new(tool_name: "reek", tool_type: "smell_detection", check: "DuplicateMethodCall", timestamp: 123, result: "call repeated", filepath: "app/example.rb", line: 2),
        Result.new(tool_name: "flog", tool_type: "complexity", check: "Complexity", timestamp: 123, result: "too complex", filepath: "app/other.rb", line: 1),
      ]
    end

    def rendered_review
      JSON.generate(
        {
          body: "Review body",
          comments: [
            { path: "app/example.rb", line: 2, body: "Inline comment" },
            { path: "app/other.rb", line: 1, body: "Ignored comment" },
          ],
        },
      )
    end
  end
end
