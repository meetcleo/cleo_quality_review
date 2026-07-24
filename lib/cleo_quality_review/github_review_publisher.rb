# frozen_string_literal: true

require "json"

require_relative "github_client"
require_relative "github_review_builder"
require_relative "llm_errors"

module CleoQualityReview
  ##
  # Publishes quality review findings as a GitHub pull request review
  class GitHubReviewPublisher
    ##
    # @param [Run] run completed quality review run
    # @param [String] rendered_review JSON produced by the pr_review formatter
    # @param [Hash{String => String}] env process environment
    # @param [GitHubClient, nil] client GitHub API client (built from env when omitted)
    def initialize(run:, rendered_review:, env: ENV, client: nil)
      @run = run
      @rendered_review = rendered_review
      @env = env
      @client = client
    end

    ##
    # Publish the review, or skip when there is no PR context/findings
    # @return [String] status message
    def publish
      skip_reason = publication_skip_reason
      return skip_reason if skip_reason

      post_review
    end

    private

    def publication_skip_reason
      review_id = run.review_id
      return "No PR review comments to publish." if builder.empty?
      return "No pull_request event found; skipping PR review publication." unless pull_request_context?
      return "PR review already published for review ID #{review_id}; skipping." if already_published?

      nil
    end

    def post_review
      response = client.post(reviews_path, builder.payload(commit_id: head_sha))
      raise Error, "GitHub PR review publication failed with status #{response.status_code}: #{response.body}" unless response.success?

      "Published PR review for review ID #{run.review_id}."
    end

    attr_reader :env, :rendered_review, :run

    def already_published?
      response = client.get(reviews_path)
      body = response.body
      raise Error, "GitHub PR review lookup failed with status #{response.status_code}: #{body}" unless response.success?

      JSON.parse(body).any? do |review|
        review.fetch("body", "").include?(builder.marker)
      end
    end

    def client
      @client ||= GitHubClient.new(token: token, api_url: api_url)
    end

    def builder
      @builder ||= GitHubReviewBuilder.new(run: run, rendered_review: rendered_review)
    end

    def pull_request_context?
      event.fetch("pull_request", nil).is_a?(Hash)
    end

    def reviews_path
      "/repos/#{repository}/pulls/#{pull_request_number}/reviews"
    end

    def pull_request_number
      event["number"] || event.fetch("pull_request").fetch("number")
    end

    def head_sha
      event.fetch("pull_request").fetch("head").fetch("sha")
    end

    def repository
      env.fetch("GITHUB_REPOSITORY")
    end

    def api_url
      env.fetch("GITHUB_API_URL", "https://api.github.com")
    end

    def event
      @event ||= JSON.parse(File.read(env.fetch("GITHUB_EVENT_PATH")))
    end

    def token
      env.fetch("GITHUB_TOKEN")
    end
  end
end
