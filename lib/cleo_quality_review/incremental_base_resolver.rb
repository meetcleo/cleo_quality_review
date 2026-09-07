# frozen_string_literal: true

require_relative "github_client"
require_relative "pull_request_context"
require_relative "sticky_comment"

module CleoQualityReview
  ##
  # Resolves the git base for an incremental review.
  #
  # On a pull request that cleo-quality-review has already reviewed, this
  # returns the previously-reviewed commit recorded on the sticky pull request
  # comment, provided it is still an ancestor of the current head, so only
  # changes made since that review are analysed. It falls back to +nil+
  # (meaning "review the full diff") outside a pull request context, when no
  # sticky comment survives in history, or on any lookup error.
  class IncrementalBaseResolver
    DISABLED_VALUES = %w[0 false no off].freeze
    ENABLED_ENV_KEY = "CLEO_QUALITY_REVIEW_INCREMENTAL"

    ##
    # @param [CommandRunner] command_runner for executing git commands
    # @param [Hash{String => String}] env process environment
    # @param [GitHubClient, nil] client GitHub API client (built from the context when omitted)
    # @param [StickyComment, nil] comment sticky comment collaborator (built from the context when omitted)
    def initialize(command_runner:, env: ENV, client: nil, comment: nil)
      @command_runner = command_runner
      @env = env
      @context = PullRequestContext.new(env: env)
      @sticky_comment = comment || StickyComment.new(client: client || default_client, context: @context)
    end

    ##
    # Resolve the incremental base commit.
    # @param [String] head git ref for the current head
    # @return [String, nil] commit SHA to diff against, or nil to review the full diff
    def resolve(head: "HEAD")
      return nil unless incremental_lookup_available?

      reviewed_commit(head)
    rescue StandardError => error
      warn("cleo-quality-review: incremental base lookup failed (#{error.message}); reviewing the full diff")
      nil
    end

    private

    attr_reader :command_runner, :env, :context, :sticky_comment

    ##
    # @return [Boolean] whether an incremental lookup can run in this context
    def incremental_lookup_available?
      enabled? && context.pull_request? && context.token && context.repository
    end

    def reviewed_commit(head)
      sha = sticky_comment.reviewed_commit_sha
      sha if sha && ancestor?(sha, head)
    end

    def ancestor?(sha, head)
      command_runner.run("git", "merge-base", "--is-ancestor", sha, head).success?
    end

    def enabled?
      !DISABLED_VALUES.include?(env.fetch(ENABLED_ENV_KEY) { "" }.to_s.strip.downcase)
    end

    def default_client
      GitHubClient.new(token: context.token, api_url: context.api_url)
    end
  end
end
