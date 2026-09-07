# frozen_string_literal: true

require_relative "github_client"
require_relative "pull_request_context"
require_relative "sticky_comment"
require_relative "sticky_comment_builder"

module CleoQualityReview
  ##
  # Coordinates publishing quality review findings as the pull request's
  # sticky comment, editing it in place on every run rather than posting a
  # new comment each time
  class StickyCommentPublisher
    STATUS_MESSAGES = { created: "Created", updated: "Updated" }.freeze

    ##
    # @param [Run] run completed quality review run
    # @param [String] rendered_review JSON produced by the pr_review formatter
    # @param [Hash{String => String}] env process environment
    # @param [GitHubClient, nil] client GitHub API client (built from the context when omitted)
    # @param [StickyComment, nil] comment sticky comment collaborator (built from the context when omitted)
    def initialize(run:, rendered_review:, env: ENV, client: nil, comment: nil)
      @run = run
      @builder = StickyCommentBuilder.new(rendered_review: rendered_review)
      @context = PullRequestContext.new(env: env)
      @comment = comment || StickyComment.new(client: client || default_client, context: context)
    end

    ##
    # Publish the sticky comment, or skip when there is no PR context/findings
    # @return [String] status message
    def publish
      skip_reason = publication_skip_reason
      return skip_reason if skip_reason

      status = comment.save!(comment_body)
      "#{STATUS_MESSAGES.fetch(status)} sticky comment for review ID #{run.review_id}."
    end

    private

    attr_reader :run, :builder, :context, :comment

    def publication_skip_reason
      return "No pull_request event found; skipping sticky comment publication." unless context.pull_request?
      return "No sticky comment to publish for review ID #{run.review_id}." if builder.empty? && !comment.exists?

      nil
    end

    def comment_body
      builder.comment_body(commit_sha: context.head_sha)
    end

    def default_client
      GitHubClient.new(token: context.token, api_url: context.api_url)
    end
  end
end
