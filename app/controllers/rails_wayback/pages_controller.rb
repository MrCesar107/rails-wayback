# frozen_string_literal: true

module RailsWayback
  # JSON endpoints consumed by the bar's JavaScript to populate the
  # branch and commit selectors. All rendering of the actual UI lives
  # in the middleware; this controller only exposes git metadata.
  class PagesController < ApplicationController
    def branches
      current_branch = safe_call { git.current_branch }
      current_commit = safe_call { git.current_commit }
      branches = safe_call { git.branches }

      render json: {
        current_branch: current_branch.value,
        current_commit: current_commit.value,
        branches: branches.value || [],
        errors: [branches.error].compact
      }
    end

    def commits
      branch = params[:branch].to_s.sub(/\.json\z/, "")
      result = safe_call { git.commits(branch) }

      list = (result.value || []).map do |commit|
        {
          sha: commit.sha,
          short_sha: commit.short_sha,
          subject: commit.subject,
          author: commit.author,
          date: commit.date
        }
      end

      render json: {
        branch: branch,
        commits: list,
        error: result.error
      }
    end

    private

    Result = Struct.new(:value, :error)

    def safe_call
      Result.new(yield, nil)
    rescue RailsWayback::Git::GitError => e
      Rails.logger.warn("[rails-wayback] #{e.class}: #{e.message}") if defined?(Rails)
      Result.new(nil, "#{e.class}: #{e.message}")
    end
  end
end
