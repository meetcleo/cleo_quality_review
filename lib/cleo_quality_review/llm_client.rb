# frozen_string_literal: true

require_relative "llm_config"
require_relative "llm_logger"
require_relative "llm_providers"

module CleoQualityReview
  ##
  # Client for generating LLM reviews using configured provider
  class LlmClient
    ##
    # @param [LlmConfig] config
    # @param [Boolean] log whether to log queries and responses
    def initialize(config: LlmConfig.new, log: false)
      @config = config
      @logger = LlmLogger.new(provider_name: config.provider, enabled: log)
      provider.validate_config(config)
    end

    ##
    # Generate a review from the given prompt
    # @param [String] prompt the format-specific prompt sent as input
    # @param [String, nil] instructions shared configuration prompt applied to
    #   every run
    # @return [String] the generated review
    def generate_review(prompt, instructions: nil)
      generate_with_logging(prompt, instructions)
    rescue StandardError => e
      log_error(prompt, e)
      raise
    end

    private

    attr_reader :config, :logger

    def generate_with_logging(prompt, instructions)
      provider_client.generate_review(prompt, instructions: instructions).tap do |response|
        log_success(prompt, response)
      end
    end

    def log_success(prompt, response)
      logger.log(query: prompt, response: response)
    end

    def log_error(prompt, error)
      logger.log(query: prompt, response: format_error(error))
    end

    def format_error(error)
      "ERROR: #{error.class}: #{error.message}"
    end

    def provider_client
      provider.build_client(config: config)
    end

    def provider
      @provider ||= LlmProviders.fetch(config.provider)
    end
  end
end
