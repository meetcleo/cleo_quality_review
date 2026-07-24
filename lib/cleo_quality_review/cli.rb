# frozen_string_literal: true

require "optparse"

require_relative "../cleo_quality_review"
require_relative "command_runner"
require_relative "formatter"
require_relative "github_review_publisher"
require_relative "incremental_base_resolver"
require_relative "options"
require_relative "runner"
require_relative "run_artifacts"

module CleoQualityReview
  ##
  # Command-line interface entry point
  class CLI
    SUBCOMMANDS = {
      "analyze" => :run_analyze,
      "render" => :run_render,
      "publish-pr-review" => :run_publish_pr_review,
    }.freeze

    ##
    # @param [Array<String>] argv command-line arguments
    # @param [IO] stdout standard output stream
    # @param [IO] stderr standard error stream
    def initialize(argv, stdout: $stdout, stderr: $stderr)
      @argv = argv
      @stdout = stdout
      @stderr = stderr
    end

    ##
    # Execute the CLI
    # @return [Integer] exit code (0 for success, 1 for error)
    def run
      dispatch_command
    rescue Error, OptionParser::ParseError, ArgumentError => error
      stderr.puts("check_quality: #{error.message}")
      1
    end

    private

    def dispatch_command
      @command_runner = CommandRunner.new
      command = argv.first
      subcommand = SUBCOMMANDS[command]

      if subcommand
        run_subcommand(subcommand, argv.drop(1))
      else
        run_one_shot(argv)
      end
    end

    attr_reader :argv, :stdout, :stderr, :command_runner

    def run_one_shot(arguments)
      options = Options.parse(arguments)
      run = build_runner(options).run
      output = Formatter.new(run: run, command_runner: command_runner).format
      print_output(output)
      0
    end

    def run_subcommand(subcommand, arguments)
      send(subcommand, arguments)
    end

    def run_analyze(arguments)
      options = Options.parse(arguments)
      run = build_runner(options).run
      stdout.puts(run.review_id)
      0
    end

    def build_runner(options)
      Runner.new(
        options: options,
        command_runner: command_runner,
        base_resolver: IncrementalBaseResolver.new(command_runner: command_runner),
      )
    end

    def run_render(arguments)
      options = Options.parse(arguments)
      run = RunArtifacts.load(review_id: options.validated_review_id).to_run(**options.run_loading_params)
      output = Formatter.new(run: run, command_runner: command_runner).format
      print_output(output)
      0
    end

    def run_publish_pr_review(arguments)
      options = Options.parse(arguments)
      run = RunArtifacts.load(review_id: options.validated_review_id).to_run(**options.run_loading_params)
      output = GitHubReviewPublisher.new(run: run, rendered_review: rendered_pr_review(options, run)).publish
      print_output(output)
      0
    end

    def print_output(output)
      stdout.puts(output) unless output.empty?
    end

    def rendered_pr_review(options, run)
      path = options.review_file || File.join(run.run_directory, "pr_review.json")
      raise OptionParser::MissingArgument, "--review-file is required or #{path} must exist" unless File.file?(path)

      File.read(path)
    end
  end
end
