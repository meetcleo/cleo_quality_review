# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "../llm_errors"
require_relative "open_ai_config"

module CleoQualityReview
  module LlmProviders
    ##
    # OpenAI provider implementation and support classes.
    module OpenAi
      ##
      # Value object representing an HTTP response from OpenAI.
      #
      # @!attribute [r] status_code
      #   @return [Integer] HTTP status code
      # @!attribute [r] body
      #   @return [String] response body
      HttpResponse = Struct.new(:status_code, :body, keyword_init: true) do
        ##
        # Check if the response indicates success.
        # @return [Boolean]
        def success?
          (200..299).cover?(status_code.to_i)
        end
      end

      ##
      # Value object for a JSON POST request to OpenAI.
      HttpRequest = Struct.new(:uri, :headers, :body, :timeout_seconds, keyword_init: true) do
        ##
        # Execute the HTTP request.
        # @param [Net::HTTP::Post] http_request prepared request
        # @yield [Net::HTTP] yields configured HTTP connection
        # @return [Object] result of the block
        def execute(http_request)
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
            http.open_timeout = timeout_seconds
            http.read_timeout = timeout_seconds
            http.write_timeout = timeout_seconds
            http.request(http_request)
          end
        end
      end

      ##
      # HTTP transport layer for OpenAI API requests.
      class HttpTransport
        ##
        # Send a POST request with JSON body.
        # @param [HttpRequest] request JSON POST request options
        # @return [HttpResponse]
        def post_json(request)
          http_request = build_request(request)
          response = perform_request(request, http_request)

          HttpResponse.new(status_code: response.code.to_i, body: response.body.to_s)
        end

        private

        def build_request(request)
          http_request = Net::HTTP::Post.new(request.uri)
          request.headers.each { |key, value| http_request[key] = value }
          http_request.body = JSON.generate(request.body)
          http_request
        end

        def perform_request(request, http_request)
          request.execute(http_request)
        end
      end

      ##
      # Client for the OpenAI Responses API.
      class Client
        RESPONSES_API_URL = URI("https://api.openai.com/v1/responses")

        ##
        # @param [Config] config OpenAI configuration
        # @param [HttpTransport] http_transport transport layer for HTTP requests
        def initialize(config:, http_transport: HttpTransport.new)
          @config = config
          @http_transport = http_transport
        end

        ##
        # Generate a review using the OpenAI Responses API.
        # @param [String] prompt the format-specific prompt to send as input
        # @param [String, nil] instructions shared configuration prompt sent as
        #   the system-level instructions applied to every run
        # @return [String] generated review text
        # @raise [ApiError] if the API request fails
        def generate_review(prompt, instructions: nil)
          response = execute_request(request_body(prompt, instructions))
          parse_response(response)
        end

        private

        attr_reader :config, :http_transport

        def execute_request(body)
          timeout_seconds = config.timeout_seconds
          http_transport.post_json(build_request(body, timeout_seconds))
        rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
          raise ApiError, timeout_error_message(timeout_seconds, e)
        end

        def parse_response(response)
          raise ApiError, api_error_message(response) unless response.success?

          extract_text(JSON.parse(response.body))
        rescue JSON::ParserError => e
          raise ApiError, "OpenAI Responses API returned invalid JSON: #{e.message}"
        end

        def build_request(body, timeout_seconds)
          HttpRequest.new(
            uri: RESPONSES_API_URL,
            headers: headers,
            body: body,
            timeout_seconds: timeout_seconds,
          )
        end

        def request_body(prompt, instructions)
          body = { model: config.model, input: prompt }
          body[:instructions] = instructions unless instructions.to_s.strip.empty?
          body
        end

        def timeout_error_message(timeout_seconds, error)
          "OpenAI Responses API request timed out after #{timeout_seconds} seconds: #{error.class}: #{error.message}"
        end

        def headers
          {
            "Authorization" => "Bearer #{config.api_key}",
            "Content-Type" => "application/json",
          }
        end

        def extract_text(response)
          output_text = response["output_text"]
          return output_text if output_text.to_s.strip != ""

          text = extract_content_text(response)
          return text unless text.empty?

          JSON.pretty_generate(response)
        end

        def extract_content_text(response)
          Array(response["output"]).flat_map { |item| extract_item_texts(item) }.join("\n")
        end

        def extract_item_texts(item)
          Array(item["content"]).filter_map { |content| content["text"] }
        end

        def api_error_message(response)
          "OpenAI Responses API request failed with status #{response.status_code}: #{response.body}"
        end
      end

      ##
      # OpenAI provider adapter for LlmClient.
      class Provider
        ##
        # Validate that the config has required OpenAI settings.
        # @param [LlmConfig] config
        # @raise [MissingLlmConfigurationError] if not configured
        # @return [void]
        def validate_config(config)
          config.open_ai_config.validate
        end

        ##
        # Build the client instance.
        # @param [LlmConfig] config
        # @return [Client]
        def build_client(config:)
          Client.new(config: config.open_ai_config)
        end
      end

      ##
      # Error raised when OpenAI API requests fail.
      class ApiError < LlmProviderError; end
    end
  end
end
