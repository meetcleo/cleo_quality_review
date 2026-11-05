# frozen_string_literal: true

require_relative "../../test_helper"
require "cleo_quality_review/llm_config"

module CleoQualityReview
  class LlmConfigTest < Minitest::Test
    def test_provider_is_openai
      config = LlmConfig.new(env: {})

      assert_equal "openai", config.provider
    end

    def test_open_ai_config_reads_api_key
      config = LlmConfig.new(env: { "CLEO_QUALITY_REVIEW_OPEN_AI_KEY" => "secret" })

      assert_instance_of LlmProviders::OpenAi::Config, config.open_ai_config
      assert_equal "secret", config.open_ai_config.api_key
    end

    def test_open_ai_config_uses_model_from_repository_configuration
      configuration = Configuration.new("LLM" => { "Model" => "gpt-5-mini" })
      config = LlmConfig.new(env: {}, configuration: configuration)

      assert_equal "gpt-5-mini", config.open_ai_config.model
    end
  end
end
