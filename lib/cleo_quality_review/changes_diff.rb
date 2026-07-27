# frozen_string_literal: true

require "digest"

require_relative "git_diff_base"

module CleoQualityReview
  ##
  # Captures the git diff used for a quality review run
  class ChangesDiff
    ##
    # @param [Array<String>] target_files files included in the review
    # @param [CommandRunner] command_runner for executing git commands
    # @param [String] base_ref git ref to compare against
    # @param [Boolean] strict_base whether unresolved refs should raise
    def initialize(target_files:, command_runner:, base_ref: GitDiffBase::DEFAULT_BASE_REF, strict_base: false)
      @target_files = target_files
      @command_runner = command_runner
      @base_ref = base_ref || GitDiffBase::DEFAULT_BASE_REF
      @strict_base = strict_base
    end

    ##
    # @return [String] combined tracked and untracked diff content, or an empty
    #   string when there are no target files to review
    def to_s
      @to_s ||= capture_diff
    end

    ##
    # @return [String] deterministic review identifier for this diff
    def review_id
      Digest::SHA256.hexdigest(to_s)
    end

    private

    attr_reader :command_runner, :target_files, :base_ref, :strict_base

    # When there are no target files there is nothing to review, so the diff is
    # empty. We must not fall back to an unscoped +git diff+, which would capture
    # the entire working tree (including untracked files such as installed gems
    # under vendor/bundle) and overflow the LLM request.
    def capture_diff
      return "" if target_files.empty?

      [tracked_changes_diff, untracked_changes_diff].reject(&:empty?).join("\n")
    end

    def tracked_changes_diff
      command_runner.run("git", "diff", diff_base, "--", *target_files).stdout
    end

    def untracked_changes_diff
      untracked_target_files.map do |filepath|
        command_runner.run("git", "diff", "--no-index", "--", "/dev/null", filepath).stdout
      end.reject(&:empty?).join("\n")
    end

    def untracked_target_files
      command_runner.run("git", "ls-files", "--others", "--exclude-standard", "--", *target_files)
        .stdout.lines.map(&:strip).select { |path| target_files.include?(path) }
    end

    def diff_base
      @diff_base ||= GitDiffBase.resolve(command_runner: command_runner, base_ref: base_ref, strict: strict_base)
    end
  end
end
