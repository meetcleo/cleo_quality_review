# frozen_string_literal: true

require_relative "../../test_helper"
require "cleo_quality_review/run"

module CleoQualityReview
  class RunTest < Minitest::Test
    def test_reviewable_when_target_files_present
      run = Run.new(target_files: ["app/example.rb"])

      assert_predicate run, :reviewable?
    end

    def test_not_reviewable_when_target_files_empty
      run = Run.new(target_files: [])

      refute_predicate run, :reviewable?
    end

    def test_not_reviewable_when_target_files_nil
      run = Run.new(target_files: nil)

      refute_predicate run, :reviewable?
    end
  end
end
