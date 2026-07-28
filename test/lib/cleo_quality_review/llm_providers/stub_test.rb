# frozen_string_literal: true

require "test_helper"
require "cleo_quality_review/llm_providers/stub"

module CleoQualityReview
  module LlmProviders
    module Stub
      class ProviderTest < Minitest::Test
        def test_provider_is_registered_as_stub
          assert_includes CleoQualityReview::LlmProviders.registered, "stub"
        end

        def test_validate_config_always_passes
          provider = Provider.new

          provider.validate_config(llm_config)
        end

        def test_client_returns_default_response
          Config.reset!

          assert_equal Config::DEFAULT_RESPONSE, stub_client.generate_review("test prompt")
        end

        def test_client_returns_configured_response
          Config.response = "custom response"

          assert_equal "custom response", stub_client.generate_review("test prompt")
        ensure
          Config.reset!
        end

        def test_client_supports_proc_response
          Config.response = ->(prompt) { "Received: #{prompt}" }

          assert_equal "Received: hello", stub_client.generate_review("hello")
        ensure
          Config.reset!
        end

        def test_client_records_received_prompts
          Config.reset!
          client = stub_client

          client.generate_review("first prompt")
          client.generate_review("second prompt")

          assert_equal ["first prompt", "second prompt"], client.received_prompts
        end

        def test_client_records_received_instructions
          Config.reset!
          client = stub_client

          client.generate_review("prompt", instructions: "shared configuration")

          assert_equal ["shared configuration"], client.received_instructions
        end

        def test_stub_config_is_always_configured
          config = Config.new(env: {})

          assert_predicate config, :configured?
        end

        private

        def stub_client
          Provider.new.build_client(config: llm_config)
        end

        def llm_config
          LlmConfig.new(env: {})
        end
      end
    end
  end
end
