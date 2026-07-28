# frozen_string_literal: true

module CleoQualityReview
  module LlmProviders
    ##
    # Stub provider implementation for tests and local development.
    module Stub
      ##
      # Configuration for the stub LLM provider.
      class Config
        DEFAULT_RESPONSE = "This is a stub review response for testing."

        class << self
          ##
          # Configure the response for all stub clients.
          # @param [String, Proc] response fixed response or callable
          # @return [void]
          def response=(response)
            @response = response
          end

          ##
          # @return [String, Proc] the configured response
          def response
            @response || DEFAULT_RESPONSE
          end

          ##
          # Reset to default response.
          # @return [void]
          def reset!
            @response = nil
          end
        end

        ##
        # @param [Hash{String => String}] env environment variables (unused, for interface compatibility)
        def initialize(env: ENV)
        end

        ##
        # @return [String] the configured response
        def response
          self.class.response
        end

        ##
        # @return [Boolean] always true for stub
        def configured?
          true
        end
      end

      ##
      # Stub LLM client, mirrors OpenAi::Client interface.
      class Client
        attr_reader :received_prompts, :received_instructions

        ##
        # @param [Config] config stub configuration
        def initialize(config:)
          @config = config
          @received_prompts = []
          @received_instructions = []
        end

        ##
        # Generate a review by returning the configured response.
        # @param [String] prompt the format-specific prompt sent as input
        # @param [String, nil] instructions shared configuration prompt applied
        #   to every run
        # @return [String] the configured response
        def generate_review(prompt, instructions: nil)
          received_prompts << prompt
          received_instructions << instructions
          response = config.response

          case response
          when Proc
            response.call(prompt)
          else
            response.to_s
          end
        end

        private

        attr_reader :config
      end

      ##
      # Stub LLM provider adapter for LlmClient.
      class Provider
        ##
        # Validate config - always passes for stub.
        # @param [LlmConfig] config
        # @return [void]
        def validate_config(config)
        end

        ##
        # Build the stub client.
        # @param [LlmConfig] config
        # @return [Client]
        def build_client(config:)
          Client.new(config: config.stub_config)
        end
      end
    end
  end
end
