# frozen_string_literal: true

require "uri"

module RailsWayback
  # JSON endpoints consumed by the bar's JavaScript to populate the
  # branch and commit selectors. All rendering of the actual UI lives
  # in the middleware; this controller only exposes git metadata.
  class PagesController < ApplicationController
    WAYBACK_COOKIES = %w[rails_wayback_ref rails_wayback_branch].freeze

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

    # Emergency escape hatch that does not render any host application view.
    # It remains usable when a historical template crashes before the injected
    # toolbar can render its normal Return to HEAD control.
    def reset
      WAYBACK_COOKIES.each { |name| response.delete_cookie(name, path: "/") }
      redirect_to safe_return_to, allow_other_host: false
    end

    private

    Result = Struct.new(:value, :error)

    def safe_call
      Result.new(yield, nil)
    rescue RailsWayback::Git::GitError => e
      Rails.logger.warn("[rails-wayback] #{e.class}: #{e.message}") if defined?(Rails)
      Result.new(nil, "#{e.class}: #{e.message}")
    end

    def safe_return_to
      target = params[:return_to].to_s
      return "/" if target.empty? || target.include?("\\")

      uri = URI.parse(target)
      return "/" unless target.start_with?("/") && !target.start_with?("//")
      return "/" if uri.scheme || uri.host

      target
    rescue URI::InvalidURIError
      "/"
    end
  end
end
