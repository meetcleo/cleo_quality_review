# frozen_string_literal: true

require "json"

require_relative "github_client"
require_relative "llm_errors"
require_relative "sticky_comment_builder"

module CleoQualityReview
  ##
  # Publishes quality review findings as a single sticky pull request
  # comment, editing it in place on every run rather than posting a new one
  class StickyCommentPublisher
    COMMENTS_PER_PAGE = 100
    MAX_COMMENT_PAGES = 20

    ##
    # @param [Run] run completed quality review run
    # @param [String] rendered_review JSON produced by the pr_review formatter
    # @param [Hash{String => String}] env process environment
    # @param [GitHubClient, nil] client GitHub API client (built from env when omitted)
    def initialize(run:, rendered_review:, env: ENV, client: nil)
      @run = run
      @env = env
      @client = client
      @builder = StickyCommentBuilder.new(rendered_review: rendered_review)
    end

    ##
    # Publish the sticky comment, or skip when there is no PR context/findings
    # @return [String] status message
    def publish
      skip_reason = publication_skip_reason
      return skip_reason if skip_reason

      existing_comment_id ? update_comment : create_comment
    end

    private

    attr_reader :env, :run, :builder

    def publication_skip_reason
      return "No pull_request event found; skipping sticky comment publication." unless pull_request_context?
      return "No sticky comment to publish for review ID #{run.review_id}." if builder.empty? && existing_comment_id.nil?

      nil
    end

    def create_comment
      response = client.post(comments_path, { body: comment_body })
      raise Error, "GitHub sticky comment creation failed with status #{response.status_code}: #{response.body}" unless response.success?

      "Created sticky comment for review ID #{run.review_id}."
    end

    def update_comment
      response = client.patch(comment_path(existing_comment_id), { body: comment_body })
      raise Error, "GitHub sticky comment update failed with status #{response.status_code}: #{response.body}" unless response.success?

      "Updated sticky comment for review ID #{run.review_id}."
    end

    def comment_body
      builder.comment_body(commit_sha: head_sha)
    end

    def existing_comment_id
      return @existing_comment_id if defined?(@existing_comment_id)

      @existing_comment_id = find_existing_comment_id
    end

    def find_existing_comment_id
      marked = comments.find { |comment| bot_authored?(comment) && marked?(comment) }
      marked && marked.fetch("id")
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
      raise Error, "GitHub comment lookup failed with status #{response.status_code}: #{response.body}" unless response.success?

      parsed = JSON.parse(response.body)
      parsed.is_a?(Array) ? parsed : []
    end

    def bot_authored?(comment)
      comment.dig("user", "type") == "Bot"
    end

    def marked?(comment)
      comment.fetch("body") { "" }.to_s.include?(StickyCommentBuilder::MARKER_PREFIX)
    end

    def client
      @client ||= GitHubClient.new(token: token, api_url: api_url)
    end

    def pull_request_context?
      event.fetch("pull_request", nil).is_a?(Hash)
    end

    def comments_path
      "/repos/#{repository}/issues/#{pull_request_number}/comments"
    end

    def comment_path(comment_id)
      "/repos/#{repository}/issues/comments/#{comment_id}"
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
