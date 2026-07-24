# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module CleoQualityReview
  ##
  # Thin authenticated HTTP client for the GitHub REST API
  class GitHubClient
    API_VERSION = "2022-11-28"
    DEFAULT_API_URL = "https://api.github.com"

    ##
    # Wrapped HTTP response
    #
    # @!attribute [r] status_code
    #   @return [Integer] HTTP status code
    # @!attribute [r] body
    #   @return [String] raw response body
    Response = Struct.new(:status_code, :body, keyword_init: true) do
      ##
      # @return [Boolean] whether the response status is in the 2xx range
      def success?
        (200..299).cover?(status_code.to_i)
      end
    end

    ##
    # @param [String] token GitHub API token
    # @param [String] api_url base GitHub API URL
    def initialize(token:, api_url: DEFAULT_API_URL)
      @token = token
      @api_url = api_url.to_s.strip.empty? ? DEFAULT_API_URL : api_url
    end

    ##
    # Perform an authenticated GET request
    # @param [String] path API path beginning with "/"
    # @return [Response]
    def get(path)
      request_json(:get, uri_for(path))
    end

    ##
    # Perform an authenticated POST request
    # @param [String] path API path beginning with "/"
    # @param [Hash] body request body serialised as JSON
    # @return [Response]
    def post(path, body)
      request_json(:post, uri_for(path), body)
    end

    private

    attr_reader :token, :api_url

    def uri_for(path)
      URI("#{api_url}#{path}")
    end

    def request_json(method, uri, body = nil)
      wrap_response(perform_request(uri, build_request(method, uri, body)))
    end

    def build_request(method, uri, body)
      request = request_class(method).new(uri)
      apply_headers(request)
      request.body = JSON.generate(body) if body
      request
    end

    def request_class(method)
      {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
      }.fetch(method) { raise ArgumentError, "Unsupported HTTP method #{method.inspect}" }
    end

    def apply_headers(request)
      github_headers.each { |key, value| request[key] = value }
    end

    def github_headers
      {
        "Accept" => "application/vnd.github+json",
        "Authorization" => "Bearer #{token}",
        "Content-Type" => "application/json",
        "User-Agent" => "cleo-quality-review",
        "X-GitHub-Api-Version" => API_VERSION,
      }
    end

    def perform_request(uri, request)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def wrap_response(response)
      Response.new(status_code: response.code.to_i, body: response.body.to_s)
    end
  end
end
