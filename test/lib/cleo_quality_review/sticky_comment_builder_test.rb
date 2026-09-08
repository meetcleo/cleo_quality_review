# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/sticky_comment_builder"

module CleoQualityReview
  class StickyCommentBuilderTest < Minitest::Test
    def test_comment_body_includes_the_marker_with_the_commit_sha
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate({ body: "Found a couple of things." }))

      assert_includes builder.comment_body(commit_sha: "head-sha"), "<!-- cleo-quality-review: commit=head-sha -->"
    end

    def test_comment_body_includes_the_rendered_narrative
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate({ body: "Found a couple of things." }))

      assert_includes builder.comment_body(commit_sha: "head-sha"), "Found a couple of things."
    end

    def test_comment_body_falls_back_to_a_clean_message_when_body_is_blank
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate({ body: "" }))

      assert_includes builder.comment_body(commit_sha: "head-sha"), "no high-confidence issues"
    end

    def test_comment_body_truncates_a_body_longer_than_the_limit
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate({ body: "x" * 4_000 }))

      assert_includes builder.comment_body(commit_sha: "head-sha"), "[truncated]"
    end

    def test_empty_is_true_when_the_rendered_body_is_blank
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate({ body: "" }))

      assert_predicate builder, :empty?
    end

    def test_empty_is_false_when_the_rendered_body_has_content
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate({ body: "Found a couple of things." }))

      refute_predicate builder, :empty?
    end

    def test_blank_rendered_review_is_treated_as_empty
      builder = StickyCommentBuilder.new(rendered_review: "")

      assert_predicate builder, :empty?
    end

    def test_invalid_json_raises
      builder = StickyCommentBuilder.new(rendered_review: "not json")

      assert_raises(Error) { builder.empty? }
    end

    def test_non_object_json_raises
      builder = StickyCommentBuilder.new(rendered_review: JSON.generate([1, 2, 3]))

      assert_raises(Error) { builder.empty? }
    end
  end
end
