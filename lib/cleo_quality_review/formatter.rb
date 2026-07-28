# frozen_string_literal: true

require_relative "llm_client"
require_relative "llm_config"
require_relative "prompt_builder"
require_relative "prompt_loader"
require_relative "run_artifacts"

module CleoQualityReview
  ##
  # Formats quality review results using an LLM with format-specific prompts
  class Formatter
    ##
    # Format name of the shared configuration prompt applied to every run
    CONFIGURATION_FORMAT = "configuration"

    ##
    # @param [Run] run the quality review run to format
    # @param [CommandRunner] command_runner for executing shell commands
    # @param [LlmConfig] llm_config LLM provider configuration
    # @param [LlmClient, nil] llm_client optional pre-configured client
    def initialize(run:, command_runner:, llm_config: LlmConfig.new, llm_client: nil)
      @run = run
      @command_runner = command_runner
      @llm_config = llm_config
      @llm_client = llm_client
    end

    ##
    # Format the run by generating an LLM review. Returns an empty string
    # without contacting the LLM when there are no files to review.
    # @return [String] formatted review text, or an empty string when there is
    #   nothing to review
    def format
      return "" unless run.reviewable?

      llm_client.generate_review(prompt, instructions: configuration_prompt)
    end

    private

    attr_reader :run, :command_runner, :llm_config

    ##
    # @return [String]
    def prompt
      PromptBuilder.new(
        run: run,
        prompt: PromptLoader.load(format: run.format),
        artifacts: artifacts,
      ).build
    end

    ##
    # Shared review rules applied to every run regardless of output format.
    # @return [String]
    def configuration_prompt
      PromptLoader.load(format: CONFIGURATION_FORMAT)
    end

    ##
    # @return [RunArtifacts]
    def artifacts
      @artifacts ||= run.artifacts || RunArtifacts.load(review_id: run.review_id || run.timestamp)
    end

    ##
    # @return [LlmClient]
    def llm_client
      @llm_client ||= LlmClient.new(config: llm_config, log: run.log)
    end
  end
end
