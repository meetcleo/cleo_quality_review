# frozen_string_literal: true

require_relative "git_diff_base"

module CleoQualityReview
  ##
  # Value object representing a quality review run with its configuration and results
  #
  # @!attribute [r] timestamp
  #   @return [Integer] epoch milliseconds when the run started
  # @!attribute [r] review_id
  #   @return [String] deterministic identifier for the reviewed diff
  # @!attribute [r] format
  #   @return [String] output format (human, agent, github)
  # @!attribute [r] checks
  #   @return [Array<String>] names of checks that were run
  # @!attribute [r] target_files
  #   @return [Array<String>] file paths that were analyzed
  # @!attribute [r] ruby_files
  #   @return [Array<String>] Ruby file paths that were analyzed
  # @!attribute [r] run_directory
  #   @return [String] path to the directory containing run artifacts
  # @!attribute [r] results
  #   @return [Array<Result>] findings from the quality checks
  # @!attribute [r] artifacts
  #   @return [RunArtifacts, nil] artifacts associated with this run
  Run = Struct.new(
    :timestamp,
    :review_id,
    :base_ref,
    :format,
    :checks,
    :target_files,
    :ruby_files,
    :run_directory,
    :results,
    :artifacts,
    :log,
    keyword_init: true,
  ) do
    ##
    # Whether the run has any files to review. Runs with no target files
    # (e.g. a branch that only changes non-Ruby files) have nothing to analyse.
    # @return [Boolean]
    def reviewable?
      !Array(target_files).empty?
    end

    ##
    # Convert the run to a hash representation
    # @return [Hash{Symbol => Object}]
    def to_h
      {
        timestamp: timestamp,
        review_id: review_id,
        base_ref: comparison_base_ref,
        format: format,
        checks: checks,
        target_files: target_files,
        ruby_files: ruby_files,
        run_directory: run_directory,
        changes_diff: artifacts&.changes_diff,
        check_outputs: check_outputs,
        findings: Array(results).map(&:to_h),
      }
    end

    ##
    # Build array of check output hashes for serialization
    # @return [Array<Hash{Symbol => String}>]
    def check_outputs
      return [] unless artifacts

      artifacts.raw_check_output_records.map(&:to_h)
    end

    ##
    # Build manifest data for artifact persistence
    # @return [Hash{Symbol => Object}]
    def manifest_data
      {
        review_id: review_id,
        base_ref: comparison_base_ref,
        timestamp: timestamp,
        checks: checks,
        target_files: target_files,
        ruby_files: ruby_files,
      }
    end

    private

    def comparison_base_ref
      base_ref || GitDiffBase::DEFAULT_BASE_REF
    end
  end
end
