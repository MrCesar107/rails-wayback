# frozen_string_literal: true

module RailsWayback
  class ReferencesController < ApplicationController
    def index
      current_branch = safe_git_call("load current Git branch") { git.current_branch }
      current_commit = safe_git_call("load current Git commit") { git.current_commit }
      references = safe_git_call("load trusted Git refs") { git.references }
      list = references.value || []

      render json: {
        current_branch: current_branch.value,
        current_commit: current_commit.value,
        branches: list.select { |reference| reference.kind == :branch }.map(&:name),
        refs: list.map { |reference| reference_json(reference) },
        errors: [current_branch, current_commit, references].filter_map do |result|
          result.failure&.summary
        end
      }
    end
  end
end
