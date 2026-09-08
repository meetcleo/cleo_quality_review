# frozen_string_literal: true

require "json"

require_relative "llm_errors"

module CleoQualityReview
  ##
  # Builds the marker and body for the sticky pull request comment from
  # rendered pr_review JSON
  class StickyCommentBuilder
    MARKER_PREFIX = "<!-- cleo-quality-review:"
    MAX_BODY_LENGTH = 3_500
    CLEAN_MESSAGE = "Cleo quality review found no high-confidence issues worth flagging on this change."

    ##
    # @param [String] rendered_review JSON produced by the pr_review formatter
    def initialize(rendered_review:)
      @rendered_review = rendered_review
    end

    ##
    # @param [String] commit_sha head commit reviewed to embed in the marker
    # @return [String] full comment body, including the hidden marker
    def comment_body(commit_sha:)
      [marker(commit_sha), truncate(display_body)].join("\n\n")
    end

    ##
    # @return [Boolean] whether the rendered review has anything worth publishing
    def empty?
      body_text.empty?
    end

    private

    attr_reader :rendered_review

    def marker(commit_sha)
      "#{MARKER_PREFIX} commit=#{commit_sha} -->"
    end

    def display_body
      body_text.empty? ? CLEAN_MESSAGE : body_text
    end

    def body_text
      parsed_review.fetch("body", "").to_s.strip
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

    def truncate(value)
      return value if value.length <= MAX_BODY_LENGTH

      "#{value[0, MAX_BODY_LENGTH - 20]}\n\n[truncated]"
    end
  end
end
