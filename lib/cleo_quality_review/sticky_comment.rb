# frozen_string_literal: true

require_relative "sticky_comment_builder"

module CleoQualityReview
  ##
  # The single sticky quality-review comment on a pull request: finds it if
  # it already exists, and creates or updates it in place
  class StickyComment
    COMMIT_PATTERN = /#{Regexp.escape(StickyCommentBuilder::MARKER_PREFIX)}\s*commit=(\S+)\s*-->/
    COMMENTS_PER_PAGE = 100
    MAX_COMMENT_PAGES = 20

    ##
    # @param [GitHubClient] client authenticated GitHub API client
    # @param [PullRequestContext] context current run's pull request context
    def initialize(client:, context:)
      @client = client
      @context = context
    end

    ##
    # @return [Boolean] whether this comment has already been posted
    def exists?
      !!existing
    end

    ##
    # @return [String, nil] the commit SHA this comment last reviewed
    def reviewed_commit_sha
      existing&.fetch("body").to_s[COMMIT_PATTERN, 1]
    end

    ##
    # Create the comment, or update it in place if it already exists
    # @param [String] body full comment body, including its marker
    # @return [Symbol] +:created+ or +:updated+
    def save!(body)
      existing ? update(body) : create(body)
    end

    private

    attr_reader :client, :context

    def create(body)
      client.post(comments_path, { body: body }).assert_success!("Sticky comment creation")
      :created
    end

    def update(body)
      client.patch(comment_path(existing.fetch("id")), { body: body }).assert_success!("Sticky comment update")
      :updated
    end

    def existing
      return @existing if defined?(@existing)

      @existing = comments.find { |comment| ours?(comment) }
    end

    def comments
      (1..MAX_COMMENT_PAGES).each_with_object([]) do |page, all|
        page_comments = comments_page(page)
        all.concat(page_comments)
        break all if page_comments.length < COMMENTS_PER_PAGE
      end
    end

    def comments_page(page)
      response = client.get("#{comments_path}?per_page=#{COMMENTS_PER_PAGE}&page=#{page}")
      response.assert_success!("Sticky comment lookup")
      response.parsed_array
    end

    ##
    # Only trust a bot-authored comment that carries our marker. A human
    # contributor could otherwise forge the marker in their own comment and
    # steer incremental review past changes the tool never analysed.
    def ours?(comment)
      bot_authored?(comment) && marked?(comment)
    end

    def bot_authored?(comment)
      comment.dig("user", "type") == "Bot"
    end

    def marked?(comment)
      comment.fetch("body") { "" }.to_s.include?(StickyCommentBuilder::MARKER_PREFIX)
    end

    def comments_path
      "/repos/#{context.repository}/issues/#{context.number}/comments"
    end

    def comment_path(comment_id)
      "/repos/#{context.repository}/issues/comments/#{comment_id}"
    end
  end
end
