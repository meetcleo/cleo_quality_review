# frozen_string_literal: true

require "json"

require_relative "github_client"
require_relative "llm_errors"

module CleoQualityReview
  ##
  # Resolves the git base for an incremental review.
  #
  # On a pull request that cleo-quality-review has already reviewed, this
  # returns the most recent previously-reviewed commit that is still an
  # ancestor of the current head, so only changes made since that review are
  # analysed. It falls back to +nil+ (meaning "review the full diff") outside a
  # pull request context, when no prior review survives in history, or on any
  # lookup error.
  class IncrementalBaseResolver
    REVIEW_MARKER_PREFIX = "<!-- cleo-quality-review:"
    DISABLED_VALUES = %w[0 false no off].freeze
    ENABLED_ENV_KEY = "CLEO_QUALITY_REVIEW_INCREMENTAL"

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
      return nil unless enabled?
      return nil unless pull_request_number && token && repository

      newest_reviewed_ancestor(head)
    rescue StandardError => error
      warn("cleo-quality-review: incremental base lookup failed (#{error.message}); reviewing the full diff")
      nil
    end

    private

    attr_reader :command_runner, :env

    def newest_reviewed_ancestor(head)
      reviewed_commit_ids.find { |sha| ancestor?(sha, head) }
    end

    def reviewed_commit_ids
      reviews
        .select { |review| quality_review?(review) }
        .sort_by { |review| review["submitted_at"].to_s }
        .reverse
        .filter_map { |review| review["commit_id"] }
        .reject { |sha| sha.to_s.strip.empty? }
        .uniq
    end

    def reviews
      response = client.get("/repos/#{repository}/pulls/#{pull_request_number}/reviews?per_page=100")
      raise Error, "GitHub review lookup returned status #{response.status_code}" unless response.success?

      parsed = JSON.parse(response.body)
      parsed.is_a?(Array) ? parsed : []
    end

    def quality_review?(review)
      review.fetch("body", "").to_s.include?(REVIEW_MARKER_PREFIX)
    end

    def ancestor?(sha, head)
      command_runner.run("git", "merge-base", "--is-ancestor", sha, head).success?
    end

    def enabled?
      !DISABLED_VALUES.include?(env.fetch(ENABLED_ENV_KEY, "").to_s.strip.downcase)
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
      env.fetch("GITHUB_API_URL", GitHubClient::DEFAULT_API_URL)
    end

    def client
      @client ||= GitHubClient.new(token: token, api_url: api_url)
    end
  end
end
