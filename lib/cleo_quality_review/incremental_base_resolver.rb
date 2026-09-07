# frozen_string_literal: true

require "json"

require_relative "github_client"
require_relative "llm_errors"
require_relative "sticky_comment_builder"

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
    MARKER_PREFIX = StickyCommentBuilder::MARKER_PREFIX
    COMMIT_PATTERN = /#{Regexp.escape(MARKER_PREFIX)}\s*commit=(\S+)\s*-->/
    DISABLED_VALUES = %w[0 false no off].freeze
    ENABLED_ENV_KEY = "CLEO_QUALITY_REVIEW_INCREMENTAL"
    COMMENTS_PER_PAGE = 100
    MAX_COMMENT_PAGES = 20

    ##
    # @param [CommandRunner] command_runner for executing git commands
    # @param [Hash{String => String}] env process environment
    # @param [GitHubClient, nil] client GitHub API client (built from env when omitted)
    def initialize(command_runner:, env: ENV, client: nil)
      @command_runner = command_runner
      @env = env
      @client = client
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

    attr_reader :command_runner, :env

    ##
    # @return [Boolean] whether an incremental lookup can run in this context
    def incremental_lookup_available?
      enabled? && !pull_request_number.nil? && !token.nil? && !repository.nil?
    end

    def reviewed_commit(head)
      sha = sticky_comment_commit_sha
      sha if sha && ancestor?(sha, head)
    end

    def sticky_comment_commit_sha
      sticky_comment = comments.find { |comment| quality_review?(comment) }
      sticky_comment && sticky_comment.fetch("body").to_s[COMMIT_PATTERN, 1]
    end

    ##
    # Fetch every issue comment, following pagination so our sticky comment is
    # not missed on pull requests with more than one page of comments.
    # @return [Array<Hash>]
    def comments
      (1..MAX_COMMENT_PAGES).each_with_object([]) do |page, all|
        page_comments = comments_page(page)
        all.concat(page_comments)
        break all if page_comments.length < COMMENTS_PER_PAGE
      end
    end

    def comments_page(page)
      response = client.get("/repos/#{repository}/issues/#{pull_request_number}/comments?per_page=#{COMMENTS_PER_PAGE}&page=#{page}")
      raise Error, "GitHub comment lookup returned status #{response.status_code}" unless response.success?

      parsed = JSON.parse(response.body)
      parsed.is_a?(Array) ? parsed : []
    end

    ##
    # Only trust a bot-authored comment that carries our marker. A human
    # contributor could otherwise forge the marker in their own comment and
    # steer the base past changes the tool never analysed.
    # @param [Hash] comment
    # @return [Boolean]
    def quality_review?(comment)
      bot_authored?(comment) && marked?(comment)
    end

    def bot_authored?(comment)
      comment.dig("user", "type") == "Bot"
    end

    def marked?(comment)
      comment.fetch("body") { "" }.to_s.include?(MARKER_PREFIX)
    end

    def ancestor?(sha, head)
      command_runner.run("git", "merge-base", "--is-ancestor", sha, head).success?
    end

    def enabled?
      !DISABLED_VALUES.include?(env.fetch(ENABLED_ENV_KEY) { "" }.to_s.strip.downcase)
    end

    def pull_request_number
      return @pull_request_number if defined?(@pull_request_number)

      @pull_request_number = event && (event["number"] || event.dig("pull_request", "number"))
    end

    def event
      return @event if defined?(@event)

      @event = load_event
    end

    def load_event
      path = env["GITHUB_EVENT_PATH"]
      return nil if path.to_s.empty? || !File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def token
      value = env["GITHUB_TOKEN"].to_s
      value unless value.empty?
    end

    def repository
      value = env["GITHUB_REPOSITORY"].to_s
      value unless value.empty?
    end

    def api_url
      env.fetch("GITHUB_API_URL") { GitHubClient::DEFAULT_API_URL }
    end

    def client
      @client ||= GitHubClient.new(token: token, api_url: api_url)
    end
  end
end
