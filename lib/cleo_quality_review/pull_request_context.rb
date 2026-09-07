# frozen_string_literal: true

require "json"

require_relative "github_client"

module CleoQualityReview
  ##
  # The pull request identity and GitHub API credentials for the current run,
  # parsed from the GitHub Actions event payload and environment
  class PullRequestContext
    ##
    # @param [Hash{String => String}] env process environment
    def initialize(env: ENV)
      @env = env
    end

    ##
    # @return [Boolean] whether this run was triggered by a pull_request event
    def pull_request?
      event.fetch("pull_request", nil).is_a?(Hash)
    end

    ##
    # @return [Integer, nil] the pull request number
    def number
      event["number"] || event.dig("pull_request", "number")
    end

    ##
    # @return [String, nil] the pull request head commit SHA
    def head_sha
      event.dig("pull_request", "head", "sha")
    end

    ##
    # @return [String, nil] the GitHub API token, or nil when unset
    def token
      presence(env["GITHUB_TOKEN"])
    end

    ##
    # @return [String, nil] the "owner/repo" slug, or nil when unset
    def repository
      presence(env["GITHUB_REPOSITORY"])
    end

    ##
    # @return [String] the GitHub REST API base URL
    def api_url
      env.fetch("GITHUB_API_URL") { GitHubClient::DEFAULT_API_URL }
    end

    private

    attr_reader :env

    def presence(value)
      value.to_s.empty? ? nil : value
    end

    def event
      @event ||= load_event
    end

    def load_event
      path = env["GITHUB_EVENT_PATH"]
      return {} if path.to_s.empty? || !File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end
  end
end
