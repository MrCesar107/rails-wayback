# frozen_string_literal: true

module RailsWayback
  class CommitsController < ApplicationController
    def index
      selector = params[:reference].to_s
      result = safe_git_call("load commits for Git ref #{selector.inspect}") do
        reference = git.reference(selector)
        [reference, git.commits(reference.full_name)]
      end
      reference, commits = result.value

      render json: {
        branch: reference&.name || selector,
        ref: reference && reference_json(reference),
        commits: Array(commits).map { |commit| commit_json(commit) },
        error: result.failure&.summary
      }
    end

    private

    def commit_json(commit)
      {
        sha: commit.sha,
        short_sha: commit.short_sha,
        subject: commit.subject,
        author: commit.author,
        date: commit.date
      }
    end
  end
end
