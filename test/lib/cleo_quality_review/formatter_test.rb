# frozen_string_literal: true

require_relative "../../test_helper"
require "cleo_quality_review/formatter"
require "cleo_quality_review/llm_config"
require "cleo_quality_review/run"

module CleoQualityReview
  class FormatterTest < Minitest::Test
    FakeLlmClient = Struct.new(:received_prompt, :received_instructions, keyword_init: true) do
      def generate_review(prompt, instructions: nil)
        self.received_prompt = prompt
        self.received_instructions = instructions
        "review output"
      end
    end

    def test_format_calls_llm_with_prompt_built_from_run
      in_tmpdir do
        FileUtils.mkdir_p("tmp/quality_checks/123/reek")
        File.write("tmp/quality_checks/123/changes.diff", "diff content")
        File.write("tmp/quality_checks/123/reek/raw_output.json", "[]")
        llm_client = FakeLlmClient.new
        run = Run.new(timestamp: 123, format: "human", target_files: ["app/example.rb"], checks: ["reek"])

        output = Formatter.new(run: run, command_runner: nil, llm_client: llm_client).format

        assert_equal "review output", output
        assert_includes llm_client.received_prompt, "Raw reek output"
      end
    end

    def test_format_passes_configuration_prompt_as_instructions
      in_tmpdir do
        FileUtils.mkdir_p("tmp/quality_checks/123/reek")
        File.write("tmp/quality_checks/123/changes.diff", "diff content")
        File.write("tmp/quality_checks/123/reek/raw_output.json", "[]")
        llm_client = FakeLlmClient.new
        run = Run.new(timestamp: 123, format: "human", target_files: ["app/example.rb"], checks: ["reek"])

        Formatter.new(run: run, command_runner: nil, llm_client: llm_client).format

        assert_includes llm_client.received_instructions, "standard rules that apply to every review"
      end
    end

    def test_format_loads_prompt_for_configured_format
      in_tmpdir do
        FileUtils.mkdir_p("tmp/quality_checks/123")
        File.write("tmp/quality_checks/123/changes.diff", "diff")
        llm_client = FakeLlmClient.new
        run = Run.new(timestamp: 123, format: "agent", target_files: ["app/example.rb"], checks: [])

        Formatter.new(run: run, command_runner: nil, llm_client: llm_client).format

        assert_includes llm_client.received_prompt, "AI coding assistants"
      end
    end

    def test_format_skips_llm_when_no_reviewable_changes
      llm_client = FakeLlmClient.new
      run = Run.new(timestamp: 123, format: "human", target_files: [], checks: [])

      output = Formatter.new(run: run, command_runner: nil, llm_client: llm_client).format

      assert_equal "", output
      assert_nil llm_client.received_prompt
    end

    def test_format_raises_when_llm_configuration_missing
      run = Run.new(timestamp: 123, format: "human", target_files: ["app/example.rb"], checks: [])
      config = LlmConfig.new(env: {})

      error = assert_raises(MissingLlmConfigurationError) do
        Formatter.new(run: run, command_runner: nil, llm_config: config).format
      end

      assert_includes error.message, "Missing OpenAI API key"
    end
  end
end
