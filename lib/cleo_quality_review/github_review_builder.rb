# frozen_string_literal: true

require "json"

require_relative "diff_map"
require_relative "llm_errors"

module CleoQualityReview
  ##
  # Builds a GitHub pull request review payload from rendered pr_review JSON
  class GitHubReviewBuilder
    MAX_INLINE_COMMENTS = 20
    MAX_BODY_LENGTH = 3_500

    ##
    # Normalized rendered comment that can be mapped onto a PR diff line
    InlineComment = Struct.new(:path, :line, :body, keyword_init: true) do
      def valid?
        path != "" && line.positive? && body != ""
      end

      def commentable_on?(diff_map)
        valid? && diff_map.commentable?(path, line)
      end

      def to_review_payload(diff_map:, truncator:)
        return unless commentable_on?(diff_map)

        { path: path, line: line, side: "RIGHT", body: truncator.call(body) }
      end
    end

    ##
    # @param [Run] run completed quality review run
    # @param [String] rendered_review JSON produced by the pr_review formatter
    def initialize(run:, rendered_review:)
      @run = run
      @rendered_review = rendered_review
      @diff_map = DiffMap.new(run.artifacts.changes_diff)
    end

    ##
    # @param [String, nil] commit_id pull request head SHA
    # @return [Hash] GitHub pull request review payload
    def payload(commit_id: nil)
      comments = inline_comments
      payload = {
        event: "COMMENT",
        body: review_body(comments),
      }
      payload[:commit_id] = commit_id if commit_id.to_s.strip != ""
      payload[:comments] = comments unless comments.empty?
      payload
    end

    ##
    # @return [String] hidden marker used to avoid duplicate reviews
    def marker
      "<!-- cleo-quality-review:#{run.review_id} -->"
    end

    ##
    # @return [Boolean] whether the rendered review contains anything useful to publish
    def empty?
      rendered_comments.empty?
    end

    private

    attr_reader :diff_map, :rendered_review, :run

    def inline_comments
      rendered_comments.first(MAX_INLINE_COMMENTS).filter_map do |comment|
        inline_comment_payload(normalized_comment(comment))
      end
    end

    def normalized_comment(comment)
      InlineComment.new(
        path: comment["path"].to_s,
        line: comment["line"].to_i,
        body: comment["body"].to_s.strip,
      )
    end

    def inline_comment_payload(comment)
      comment.to_review_payload(diff_map: diff_map, truncator: method(:truncate))
    end

    def rendered_comments
      comments = parsed_review.fetch("comments", [])
      raise Error, "pr_review JSON field \"comments\" must be an array" unless comments.is_a?(Array)

      comments
    end

    def parsed_review
      @parsed_review ||= parse_rendered_review
    end

    # A blank rendered review (e.g. the render step produced no output because
    # there were no reviewable changes) means there is nothing to publish, so
    # treat it as an empty review rather than failing to parse it as JSON.
    def parse_rendered_review
      content = rendered_review.to_s.strip
      return {} if content.empty?

      parsed = JSON.parse(content)
      raise Error, "pr_review JSON must be an object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise Error, "pr_review output was not valid JSON: #{e.message}"
    end

    def review_body(comments)
      [
        marker,
        body_text,
        inline_summary(comments),
      ].compact.join("\n\n")
    end

    def body_text
      parsed_review.fetch("body", "").to_s.strip
    end

    def inline_summary(comments)
      published_count = comments.length
      requested_count = rendered_comments.length
      omitted_comments_message(published_count, requested_count)
    end

    def omitted_comments_message(published, requested)
      return "No rendered comments mapped to commentable PR diff lines." if published.zero? && requested.positive?
      return if published == requested

      omitted = requested - published
      "#{omitted} rendered comment#{'s' unless omitted == 1} were omitted because they did not map to commentable PR diff lines."
    end

    def truncate(value)
      return value if value.length <= MAX_BODY_LENGTH

      "#{value[0, MAX_BODY_LENGTH - 20]}\n\n[truncated]"
    end
  end
end
