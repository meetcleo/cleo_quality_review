# frozen_string_literal: true

require_relative "configuration"
require_relative "llm_providers/open_ai_config"

module CleoQualityReview
  ##
  # Configuration for LLM provider
  class LlmConfig
    PROVIDER = "openai"

    ##
    # @param [Hash{String => String}] env environment variables
    # @param [Configuration] configuration repository configuration
    def initialize(env: ENV, configuration: Configuration.load)
      @env = env
      @configuration = configuration
    end

    ##
    # @return [String] the provider name
    def provider
      PROVIDER
    end

    ##
    # @return [LlmProviders::OpenAi::Config]
    def open_ai_config
      @open_ai_config ||= LlmProviders::OpenAi::Config.new(env: env, model: configuration.llm_model)
    end

    ##
    # @return [LlmProviders::Stub::Config]
    def stub_config
      require_relative "llm_providers/stub"
      @stub_config ||= LlmProviders::Stub::Config.new(env: env)
    end

    private

    attr_reader :env, :configuration
  end
end
