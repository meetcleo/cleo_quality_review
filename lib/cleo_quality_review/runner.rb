# frozen_string_literal: true

require "digest"
require "forwardable"
require "json"

require_relative "changes_diff"
require_relative "checks"
require_relative "command_runner"
require_relative "concurrent_executor"
require_relative "git_diff_base"
require_relative "run"
require_relative "run_artifacts"
require_relative "target_resolver"

module CleoQualityReview
  ##
  # Orchestrates a complete quality review run
  class Runner
    extend Forwardable

    ##
    # Grouped values resolved at the start of an analysis run
    AnalysisContext = Struct.new(:timestamp, :base_ref, :target, :changes, :review_id, :check_classes, keyword_init: true) do
      ##
      # @return [Hash] run construction attributes derived from this context
      def run_attributes
        {
          timestamp: timestamp,
          base_ref: base_ref,
          review_id: review_id,
          checks: check_classes.map(&:check_name),
          target_files: target.files,
          ruby_files: target.ruby_files,
        }
      end
    end

    ##
    # Runtime collaborators for a quality review run
    Dependencies = Struct.new(:command_runner, :clock, :check_registry, :base_resolver, :executor, keyword_init: true) do
      def self.for(options, overrides)
        new(
          **{
            command_runner: CommandRunner.new,
            clock: Time,
            check_registry: Checks,
            base_resolver: nil,
            executor: ConcurrentExecutor.new(max_workers: options.jobs),
          }.merge(overrides),
        )
      end
    end

    ##
    # @param [Options::ParseResult] options parsed command-line options
    # @param [Hash] dependencies optional runtime collaborators for tests or alternate runners
    def initialize(options:, **dependencies)
      @options = options
      @dependencies = Dependencies.for(options, dependencies)
    end

    ##
    # Execute the quality review
    # @return [Run] results of the quality review
    def run
      context = analysis_context
      artifacts = prepare_artifacts(context)
      return reusable_run(artifacts) if artifacts.complete?

      execute_fresh_run(context, artifacts)
    end

    private

    attr_reader :options, :dependencies
    def_delegators :dependencies, :command_runner, :clock, :check_registry, :base_resolver, :executor
    private :command_runner, :clock, :check_registry, :base_resolver, :executor

    def epoch_milliseconds
      (clock.now.to_r * 1_000).to_i
    end

    def analysis_context
      timestamp = epoch_milliseconds
      target = resolve_target
      changes = changes_diff(target)
      check_classes = resolve_checks

      AnalysisContext.new(
        timestamp: timestamp,
        base_ref: base_ref,
        target: target,
        changes: changes,
        review_id: review_id_for(changes, check_classes, base_ref: base_ref),
        check_classes: check_classes,
      )
    end

    def resolve_target
      files = options.files
      TargetResolver.new(command_runner: command_runner, base_ref: base_ref).resolve(files, changed: changed_mode?)
    end

    def changes_diff(target)
      ChangesDiff.new(
        target_files: target.files,
        command_runner: command_runner,
        base_ref: base_ref,
        strict_base: changed_mode?,
      )
    end

    def prepare_artifacts(context)
      RunArtifacts.new(
        timestamp: context.timestamp,
        review_id: context.review_id,
        target_files: context.target.files,
        changes_diff: context.changes.to_s,
      ).prepare!
    end

    def reusable_run(artifacts)
      artifacts.to_run(format: options.format, log: options.log)
    end

    def execute_fresh_run(context, artifacts)
      check_outputs = run_checks(context.check_classes, context.target.ruby_files, context.timestamp)
      write_check_outputs(artifacts, check_outputs)
      run = build_run(context, artifacts, check_outputs)
      persist_run(artifacts, run)
      run
    end

    def resolve_checks
      all_checks = check_registry.resolve(options.checks)
      filter_excluded_checks(all_checks, options.exclude)
    end

    def filter_excluded_checks(checks, excluded)
      return checks if excluded.empty?

      excluded_names = excluded.map(&:downcase)
      checks.reject { |check| excluded_names.include?(check.check_name.downcase) }
    end

    def run_checks(check_classes, ruby_files, timestamp)
      return [] if ruby_files.empty?

      executor.map(check_classes) do |check_class|
        check_class.new(command_runner: command_runner, timestamp: timestamp).run(ruby_files)
      end
    end

    def write_check_outputs(artifacts, check_outputs)
      check_outputs.each do |output|
        artifacts.write_check_output(output)
      end
    end

    def build_run(context, artifacts, check_outputs)
      Run.new(
        **context.run_attributes,
        format: options.format,
        run_directory: artifacts.to_s,
        results: check_outputs.flat_map(&:results),
        artifacts: artifacts,
        log: options.log,
      )
    end

    def persist_run(artifacts, run)
      artifacts.write_run(run)
    end

    def review_id_for(changes, check_classes, base_ref:)
      payload = {
        diff: changes.to_s,
        checks: check_classes.map(&:check_name).sort,
      }
      payload[:base_ref] = base_ref unless base_ref == GitDiffBase::DEFAULT_BASE_REF

      Digest::SHA256.hexdigest(
        JSON.generate(payload),
      )
    end

    def changed_mode?
      options.changed || options.files.empty?
    end

    def base_ref
      @base_ref ||= base_resolver&.resolve || default_base_ref
    end

    def default_base_ref
      options.base || GitDiffBase::DEFAULT_BASE_REF
    end
  end
end
