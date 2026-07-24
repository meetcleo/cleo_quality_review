# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "uri"
require "cleo_quality_review/github_client"

module CleoQualityReview
  class GitHubClientTest < Minitest::Test
    FakeHTTPResponse = Struct.new(:code, :body, keyword_init: true)

    def test_get_targets_the_expected_uri
      client = GitHubClient.new(token: "secret", api_url: "https://api.example")
      captured = capture_request(client, FakeHTTPResponse.new(code: "200", body: "[]"))
      client.get("/repos/owner/repo/pulls/1/reviews")

      assert_equal "https://api.example/repos/owner/repo/pulls/1/reviews", captured.fetch(:uri).to_s
    end

    def test_get_sends_bearer_authorization_header
      client = GitHubClient.new(token: "secret", api_url: "https://api.example")
      captured = capture_request(client, FakeHTTPResponse.new(code: "200", body: "[]"))
      client.get("/x")

      assert_equal "Bearer secret", captured.fetch(:request)["Authorization"]
    end

    def test_get_wraps_a_successful_response
      client = GitHubClient.new(token: "t")
      capture_request(client, FakeHTTPResponse.new(code: "200", body: "[]"))

      assert_predicate client.get("/x"), :success?
    end

    def test_non_2xx_response_is_not_successful
      client = GitHubClient.new(token: "t")
      capture_request(client, FakeHTTPResponse.new(code: "404", body: "not found"))

      refute_predicate client.get("/x"), :success?
    end

    def test_post_serialises_the_body_as_json
      client = GitHubClient.new(token: "t", api_url: "https://api.example")
      captured = capture_request(client, FakeHTTPResponse.new(code: "201", body: "{}"))
      client.post("/x", { event: "COMMENT" })

      assert_equal JSON.generate({ event: "COMMENT" }), captured.fetch(:request).body
    end

    def test_blank_api_url_falls_back_to_the_default
      client = GitHubClient.new(token: "t", api_url: "")
      captured = capture_request(client, FakeHTTPResponse.new(code: "200", body: "[]"))
      client.get("/x")

      assert_equal "https://api.github.com/x", captured.fetch(:uri).to_s
    end

    def test_unsupported_method_raises
      client = GitHubClient.new(token: "t")

      assert_raises(ArgumentError) { client.send(:request_json, :put, URI("https://example/x")) }
    end

    private

    def capture_request(client, http_response)
      captured = {}
      client.define_singleton_method(:perform_request) do |uri, request|
        captured[:uri] = uri
        captured[:request] = request
        http_response
      end
      captured
    end
  end
end
