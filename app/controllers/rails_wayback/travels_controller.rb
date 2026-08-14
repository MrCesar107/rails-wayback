# frozen_string_literal: true

require "uri"

module RailsWayback
  class TravelsController < ApplicationController
    WAYBACK_COOKIES = %w[rails_wayback_ref rails_wayback_branch].freeze
    COOKIE_OPTIONS = { httponly: true, same_site: :lax, path: "/" }.freeze

    def create
      return render_unconfirmed unless params[:confirmed] == "true"

      selection = RailsWayback::RefPolicy.new.authorize(params[:ref])
      return render_rejection(selection) if selection.rejected?

      cookies["rails_wayback_ref"] = COOKIE_OPTIONS.merge(value: selection.sha)
      write_branch_cookie(selection.trusted_refs)
      redirect_to safe_return_to, allow_other_host: false
    rescue RailsWayback::Git::GitError => e
      render plain: e.message, status: :service_unavailable
    end

    def destroy
      WAYBACK_COOKIES.each { |name| response.delete_cookie(name, path: "/") }
      redirect_to safe_return_to, allow_other_host: false
    end

    private

    def write_branch_cookie(trusted_refs)
      branch = canonical_branch(params[:branch], trusted_refs)
      if branch
        cookies["rails_wayback_branch"] = COOKIE_OPTIONS.merge(value: branch)
      else
        response.delete_cookie("rails_wayback_branch", path: "/")
      end
    end

    def canonical_branch(value, trusted_refs)
      selector = value.to_s
      return if selector.empty?

      RailsWayback::GitReference.find(trusted_refs, selector)
    end

    def render_rejection(selection)
      render plain: selection.message, status: :unprocessable_content
    end

    def render_unconfirmed
      render plain: "Confirm that you trust this historical commit before traveling.",
             status: :unprocessable_content
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
