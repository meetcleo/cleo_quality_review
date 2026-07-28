# frozen_string_literal: true

require_relative "../../../test_helper"
require "cleo_quality_review/llm_providers/open_ai"

module CleoQualityReview
  module LlmProviders
    module OpenAi
      class ClientTest < Minitest::Test
        FakeConfig = Struct.new(:api_key, :model, :timeout_seconds, keyword_init: true)
        FakeTransport = Struct.new(:response, :error, :received_request, keyword_init: true) do
          def post_json(request)
            self.received_request = request
            raise error if error

            response
          end
        end

        def test_calls_responses_api_and_extracts_output_text
          transport = FakeTransport.new(response: HttpResponse.new(status_code: 200, body: JSON.generate("output_text" => "analysis")))
          client = Client.new(
            config: FakeConfig.new(api_key: "secret", model: "gpt-5.5", timeout_seconds: 180),
            http_transport: transport,
          )

          assert_equal "analysis", client.generate_review("prompt")
          assert_responses_api_request(transport.received_request)
        end

        def test_includes_configuration_instructions_in_request_body
          transport = FakeTransport.new(response: HttpResponse.new(status_code: 200, body: JSON.generate("output_text" => "analysis")))
          client = Client.new(
            config: FakeConfig.new(api_key: "secret", model: "gpt-5.5", timeout_seconds: 180),
            http_transport: transport,
          )

          client.generate_review("prompt", instructions: "shared rules")

          assert_equal(
            { model: "gpt-5.5", input: "prompt", instructions: "shared rules" },
            transport.received_request.body,
          )
        end

        def test_omits_instructions_when_not_provided
          transport = FakeTransport.new(response: HttpResponse.new(status_code: 200, body: JSON.generate("output_text" => "analysis")))
          client = Client.new(
            config: FakeConfig.new(api_key: "secret", model: "gpt-5.5", timeout_seconds: 180),
            http_transport: transport,
          )

          client.generate_review("prompt")

          refute_includes transport.received_request.body.keys, :instructions
        end

        def test_http_transport_configures_net_http_timeouts
          http_start = HttpStartRecorder.new
          response = post_json_with_stubbed_start(http_start)

          assert_success_response(response)
          assert_http_connection(http_start)
        end

        def test_extracts_nested_response_text
          response = {
            "output" => [
              {
                "content" => [
                  { "text" => "first" },
                  { "text" => "second" },
                ],
              },
            ],
          }
          transport = FakeTransport.new(response: HttpResponse.new(status_code: 200, body: JSON.generate(response)))
          client = Client.new(
            config: FakeConfig.new(api_key: "secret", model: "gpt-5.5", timeout_seconds: 180),
            http_transport: transport,
          )

          assert_equal "first\nsecond", client.generate_review("prompt")
        end

        def test_raises_clear_error_for_api_failure
          error = api_error_from(response: HttpResponse.new(status_code: 401, body: "unauthorized"))

          assert_error_message_includes(error, "status 401", "unauthorized")
        end

        def test_wraps_net_timeout_errors
          error = api_error_from(error: Net::ReadTimeout.new("request timed out"))

          assert_error_message_includes(error, "timed out after 180 seconds", "Net::ReadTimeout")
        end

        private

        def assert_responses_api_request(request)
          assert_equal URI("https://api.openai.com/v1/responses"), request.uri
          assert_authorization_headers(request.headers)
          assert_equal({ model: "gpt-5.5", input: "prompt" }, request.body)
          assert_equal 180, request.timeout_seconds
        end

        def assert_authorization_headers(headers)
          assert_equal "Bearer secret", headers.fetch("Authorization")
          assert_equal "application/json", headers.fetch("Content-Type")
        end

        def assert_success_response(response)
          assert_equal 200, response.status_code
        end

        def assert_http_connection(http_start)
          assert_http_start(http_start)
          assert_http_timeouts(http_start.http)
        end

        def assert_http_start(http_start)
          assert_equal "api.openai.com", http_start.hostname
          assert_equal 443, http_start.port
          assert_equal true, http_start.use_ssl
        end

        def assert_http_timeouts(fake_http)
          assert_equal 180, fake_http.open_timeout
          assert_equal 180, fake_http.read_timeout
          assert_equal 180, fake_http.write_timeout
        end

        def open_ai_request
          HttpRequest.new(
            uri: URI("https://api.openai.com/v1/responses"),
            headers: { "Content-Type" => "application/json" },
            body: { input: "prompt" },
            timeout_seconds: 180,
          )
        end

        def post_json_with_stubbed_start(http_start)
          NetHttpStartStub.new(http_start).with_stub do
            HttpTransport.new.post_json(open_ai_request)
          end
        end

        def client_for(transport)
          Client.new(
            config: FakeConfig.new(api_key: "secret", model: "gpt-5.5", timeout_seconds: 180),
            http_transport: transport,
          )
        end

        def api_error_from(response: nil, error: nil)
          transport = FakeTransport.new(response: response, error: error)

          assert_raises(ApiError) { client_for(transport).generate_review("prompt") }
        end

        def assert_error_message_includes(error, *messages)
          messages.each { |message| assert_includes error.message, message }
        end

        class FakeHttp
          attr_accessor :open_timeout, :read_timeout, :write_timeout

          def request(_request)
            Struct.new(:code, :body).new("200", JSON.generate("output_text" => "ok"))
          end
        end

        class HttpStartRecorder
          attr_reader :hostname, :port, :use_ssl, :http

          def initialize(http: FakeHttp.new)
            @http = http
          end

          def call(hostname, port, use_ssl:, &block)
            @hostname = hostname
            @port = port
            @use_ssl = use_ssl

            block.call(http)
          end
        end

        class NetHttpStartStub
          ALIAS_NAME = :start_without_timeout_test

          def initialize(http_start)
            @http_start = http_start
            @singleton_class = Net::HTTP.singleton_class
          end

          def with_stub
            silence_warnings { replace_start }
            yield
          ensure
            silence_warnings { restore_start }
          end

          private

          attr_reader :http_start, :singleton_class

          def replace_start
            singleton_class.alias_method(ALIAS_NAME, :start)
            start_callable = http_start
            Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
              start_callable.call(*args, **kwargs, &block)
            end
          end

          def restore_start
            singleton_class.alias_method(:start, ALIAS_NAME)
            singleton_class.remove_method(ALIAS_NAME)
          end

          def silence_warnings
            original_verbose = $VERBOSE
            $VERBOSE = nil
            yield
          ensure
            $VERBOSE = original_verbose
          end
        end
      end
    end
  end
end
