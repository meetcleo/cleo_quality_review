# frozen_string_literal: true

require_relative "../../test_helper"
require "cleo_quality_review/llm_client"
require "cleo_quality_review/llm_logger"

module CleoQualityReview
  class LlmClientTest < Minitest::Test
    def test_rejects_missing_openai_configuration
      config = LlmConfig.new(env: {})

      error = assert_raises(MissingLlmConfigurationError) do
        LlmClient.new(config: config)
      end

      assert_includes error.message, "Missing OpenAI API key"
    end

    def test_generate_review_calls_logger_log
      in_tmpdir do
        config = LlmConfig.new(env: { "CLEO_QUALITY_REVIEW_OPEN_AI_KEY" => "test-key" })
        client = LlmClient.new(config: config, log: true)
        stubbed_provider_client = StubProviderClient.new("test review")
        client.define_singleton_method(:provider_client) { stubbed_provider_client }

        result = client.generate_review("test prompt")

        assert_equal "test review", result
        assert File.exist?("log/openai.log"), "Expected log file to be created"
        log_content = File.read("log/openai.log")
        assert_includes log_content, "test prompt"
        assert_includes log_content, "test review"
      end
    end

    def test_generate_review_forwards_instructions_to_provider
      in_tmpdir do
        config = LlmConfig.new(env: { "CLEO_QUALITY_REVIEW_OPEN_AI_KEY" => "test-key" })
        client = LlmClient.new(config: config)
        stubbed_provider_client = StubProviderClient.new("test review")
        client.define_singleton_method(:provider_client) { stubbed_provider_client }

        client.generate_review("test prompt", instructions: "shared configuration")

        assert_equal "shared configuration", stubbed_provider_client.received_instructions
      end
    end

    def test_does_not_log_when_log_disabled
      in_tmpdir do
        config = LlmConfig.new(env: { "CLEO_QUALITY_REVIEW_OPEN_AI_KEY" => "test-key" })
        client = LlmClient.new(config: config, log: false)
        stubbed_provider_client = StubProviderClient.new("test review")
        client.define_singleton_method(:provider_client) { stubbed_provider_client }

        client.generate_review("test prompt")

        refute File.exist?("log/openai.log"), "Expected no log file when logging disabled"
      end
    end

    def test_logs_errors_when_provider_raises
      in_tmpdir do
        config = LlmConfig.new(env: { "CLEO_QUALITY_REVIEW_OPEN_AI_KEY" => "test-key" })
        client = LlmClient.new(config: config, log: true)
        failing_client = FailingProviderClient.new(RuntimeError.new("API failed"))
        client.define_singleton_method(:provider_client) { failing_client }

        assert_raises(RuntimeError) { client.generate_review("test prompt") }

        assert File.exist?("log/openai.log"), "Expected log file to be created even on error"
        log_content = File.read("log/openai.log")
        assert_includes log_content, "test prompt"
        assert_includes log_content, "ERROR: RuntimeError: API failed"
      end
    end
  end

  class StubProviderClient
    attr_reader :received_instructions

    def initialize(response)
      @response = response
    end

    def generate_review(_prompt, instructions: nil)
      @received_instructions = instructions
      @response
    end
  end

  class FailingProviderClient
    def initialize(error)
      @error = error
    end

    def generate_review(_prompt, instructions: nil)
      raise @error
    end
  end
end
