# frozen_string_literal: true

require "uri"

module RailsWayback
  # JSON endpoints consumed by the bar's JavaScript to populate the
  # branch and commit selectors. All rendering of the actual UI lives
  # in the middleware; this controller only exposes git metadata.
  class PagesController < ApplicationController
    WAYBACK_COOKIES = %w[rails_wayback_ref rails_wayback_branch].freeze
    Result = Struct.new(:value, :error)
    private_constant :Result

    def branches
      current_branch = safe_call { git.current_branch }
      current_commit = safe_call { git.current_commit }
      references = safe_call { git.references }
      list = references.value || []

      render json: {
        current_branch: current_branch.value,
        current_commit: current_commit.value,
        branches: list.select { |reference| reference.kind == :branch }.map(&:name),
        refs: list.map { |reference| reference_json(reference) },
        errors: [references.error].compact
      }
    end

    def commits
      selector = params[:branch].to_s.sub(/\.json\z/, "")
      result = safe_call do
        reference = git.reference(selector)
        [reference, git.commits(reference.full_name)]
      end
      reference, commits = result.value

      list = (commits || []).map do |commit|
        {
          sha: commit.sha,
          short_sha: commit.short_sha,
          subject: commit.subject,
          author: commit.author,
          date: commit.date
        }
      end

      render json: {
        branch: reference&.name || selector,
        ref: reference && reference_json(reference),
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

    def safe_call
      Result.new(yield, nil)
    rescue RailsWayback::Git::GitError => e
      Rails.logger.warn("[rails-wayback] #{e.class}: #{e.message}") if defined?(Rails)
      Result.new(nil, "#{e.class}: #{e.message}")
    end

    def reference_json(reference)
      {
        full_name: reference.full_name,
        name: reference.name,
        type: reference.kind,
        label: reference.label
      }
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
