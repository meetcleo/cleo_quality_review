# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "cleo_quality_review/run"
require "cleo_quality_review/sticky_comment_publisher"

module CleoQualityReview
  class StickyCommentPublisherTest < Minitest::Test
    FakeStickyComment = Struct.new(:existing, :saved, keyword_init: true) do
      def exists?
        existing
      end

      def save!(body)
        saved << body
        existing ? :updated : :created
      end
    end

    def test_publish_when_there_is_no_pull_request_event_skips
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "push" => {} }))
        publisher = StickyCommentPublisher.new(
          run: Run.new(review_id: "review-id"),
          rendered_review: JSON.generate({ body: "Found a couple of things." }),
          env: { "GITHUB_EVENT_PATH" => event_path },
          comment: FakeStickyComment.new(existing: false, saved: []),
        )

        assert_equal "No pull_request event found; skipping sticky comment publication.", publisher.publish
      end
    end

    def test_publish_when_nothing_to_report_and_no_existing_comment_skips
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        comment = FakeStickyComment.new(existing: false, saved: [])
        publisher = StickyCommentPublisher.new(
          run: Run.new(review_id: "review-id"),
          rendered_review: JSON.generate({ body: "" }),
          env: { "GITHUB_EVENT_PATH" => event_path },
          comment: comment,
        )

        assert_equal "No sticky comment to publish for review ID review-id.", publisher.publish
        assert_empty comment.saved
      end
    end

    def test_publish_when_no_comment_exists_creates_one
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        comment = FakeStickyComment.new(existing: false, saved: [])
        publisher = StickyCommentPublisher.new(
          run: Run.new(review_id: "review-id"),
          rendered_review: JSON.generate({ body: "Found a couple of things." }),
          env: { "GITHUB_EVENT_PATH" => event_path },
          comment: comment,
        )

        assert_equal "Created sticky comment for review ID review-id.", publisher.publish
        assert_includes comment.saved.first, "commit=head-sha"
        assert_includes comment.saved.first, "Found a couple of things."
      end
    end

    def test_publish_when_a_comment_already_exists_updates_it
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        comment = FakeStickyComment.new(existing: true, saved: [])
        publisher = StickyCommentPublisher.new(
          run: Run.new(review_id: "review-id"),
          rendered_review: JSON.generate({ body: "Found a couple of things." }),
          env: { "GITHUB_EVENT_PATH" => event_path },
          comment: comment,
        )

        assert_equal "Updated sticky comment for review ID review-id.", publisher.publish
      end
    end

    def test_publish_when_nothing_remains_to_report_but_a_comment_exists_updates_it_to_a_clean_message
      in_tmpdir do |dir|
        event_path = File.join(dir, "event.json")
        File.write(event_path, JSON.generate({ "number" => 42, "pull_request" => { "head" => { "sha" => "head-sha" } } }))
        comment = FakeStickyComment.new(existing: true, saved: [])
        publisher = StickyCommentPublisher.new(
          run: Run.new(review_id: "review-id"),
          rendered_review: JSON.generate({ body: "" }),
          env: { "GITHUB_EVENT_PATH" => event_path },
          comment: comment,
        )

        publisher.publish

        assert_includes comment.saved.first, "no high-confidence issues"
      end
    end
  end
end
