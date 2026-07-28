# frozen_string_literal: true

require "optparse"

require_relative "git_diff_base"

module CleoQualityReview
  ##
  # Parses command-line options for the quality review CLI
  class Options
    FORMATS = %w[human agent github pr_review].freeze
    DEFAULT_FORMAT = "human"
    DEFAULT_CHECKS = ["all"].freeze
    OPTION_REGISTRATIONS = [
      :register_format_option,
      :register_check_options,
      :register_target_options,
      :register_output_options,
      :register_jobs_option,
      :register_help_option,
    ].freeze

    ##
    # Value object containing parsed command-line options
    #
    # @!attribute [r] format
    #   @return [String] output format
    # @!attribute [r] checks
    #   @return [Array<String>] checks to run
    # @!attribute [r] files
    #   @return [Array<String>] explicit file paths
    # @!attribute [r] exclude
    #   @return [Array<String>] checks to exclude
    # @!attribute [r] changed
    #   @return [Boolean] whether to filter to changed files only
    # @!attribute [r] jobs
    #   @return [Integer, nil] max checks to run in parallel, or nil to auto-size
    ParseResult = Struct.new(:format, :checks, :files, :exclude, :changed, :base, :log, :review_id, :review_file, :jobs, keyword_init: true) do
      ##
      # @return [String] validated review_id
      # @raise [OptionParser::MissingArgument] if review_id is blank
      def validated_review_id
        raise OptionParser::MissingArgument, "--review-id is required" if review_id.to_s.strip == ""

        review_id
      end

      ##
      # @return [Hash] run loading attributes
      def run_loading_params
        { format: format, log: log }
      end
    end

    ##
    # Parse command-line arguments
    # @param [Array<String>] argv command-line arguments
    # @return [ParseResult]
    # @raise [OptionParser::ParseError] if arguments are invalid
    def self.parse(argv)
      new(argv).parse
    end

    ##
    # @param [Array<String>] argv command-line arguments
    def initialize(argv)
      @argv = argv.dup
      @format = DEFAULT_FORMAT
      @checks = []
      @files = []
      @exclude = []
      @changed = false
      @base = GitDiffBase::DEFAULT_BASE_REF
      @log = false
      @review_id = nil
      @review_file = nil
      @jobs = nil
    end

    ##
    # Parse the arguments and return the result
    # @return [ParseResult]
    # @raise [OptionParser::InvalidArgument] if format is invalid
    def parse
      parser.parse!(argv)
      validate_format!
      files.concat(argv)

      ParseResult.new(
        format: format,
        checks: checks.empty? ? DEFAULT_CHECKS.dup : checks,
        files: files,
        exclude: exclude,
        changed: changed,
        base: base,
        log: log,
        review_id: review_id,
        review_file: review_file,
        jobs: jobs,
      )
    end

    private

    attr_reader :argv, :format, :checks, :files, :exclude, :changed, :base, :log, :review_id, :review_file, :jobs

    def parser
      OptionParser.new do |opts|
        opts.banner = "Usage: check_quality [options] [files...]"
        register_options(opts)
      end
    end

    def register_options(opts)
      OPTION_REGISTRATIONS.each { |registration| send(registration, opts) }
    end

    def register_jobs_option(opts)
      opts.on("-j", "--jobs N", Integer, "Max checks to run in parallel (default: CPU cores)") do |value|
        @jobs = value
      end
    end

    def register_format_option(opts)
      opts.on("-f", "--format FORMAT", FORMATS, "Output format: #{FORMATS.join(', ')} (default: human)") do |value|
        @format = value
      end
    end

    def register_check_options(opts)
      register_checks_option(opts)
      register_only_option(opts)
      register_exclude_option(opts)
    end

    def register_checks_option(opts)
      opts.on("-c", "--checks CHECKS", Array, "Checks to run: all, reek, flog, fasterer") { |values| checks.concat(values) }
    end

    def register_only_option(opts)
      opts.on("--only CHECKS", Array, "Alias for --checks") { |values| checks.concat(values) }
    end

    def register_exclude_option(opts)
      opts.on("-x", "--exclude CHECKS", Array, "Checks to exclude: reek, flog, fasterer") { |values| exclude.concat(values) }
    end

    def register_target_options(opts)
      opts.on("--files PATHS", Array, "Comma-separated files or directories to check") do |values|
        files.concat(values)
      end

      opts.on("--changed", "Only check files changed from the base ref") do
        @changed = true
      end

      opts.on("--base REF", "Git ref to compare changed files against") do |value|
        @base = value
      end
    end

    def register_output_options(opts)
      register_log_option(opts)
      register_review_id_option(opts)
      register_review_file_option(opts)
    end

    def register_log_option(opts)
      opts.on("--log", "Log LLM queries and responses to log/[provider].log") { @log = true }
    end

    def register_review_id_option(opts)
      opts.on("--review-id REVIEW_ID", "Reuse an existing analysis artifact by review ID") { |value| @review_id = value }
    end

    def register_review_file_option(opts)
      opts.on("--review-file PATH", "Rendered pr_review JSON to publish") { |value| @review_file = value }
    end

    def register_help_option(opts)
      opts.on("-h", "--help", "Print help") do
        puts opts
        exit 0
      end
    end

    def validate_format!
      return if FORMATS.include?(format)

      raise OptionParser::InvalidArgument, "format must be one of: #{FORMATS.join(', ')}"
    end
  end
end
