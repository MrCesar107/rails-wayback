# frozen_string_literal: true

require "rails_wayback/asset_provenance"
require "rails_wayback/engine_mount"
require "rails_wayback/failure_boundary"
require "rails_wayback/git_reference"
require "rails_wayback/ref_policy"
require "rails_wayback/render_provenance"
require "rails_wayback/travel_request"

module RailsWayback
  class ToolbarState
    def initialize(env:, tracker:, git: RailsWayback::Git.new,
                   travel_request: RailsWayback::TravelRequest.new(env),
                   configuration: RailsWayback.configuration,
                   failure_boundary: RailsWayback::FailureBoundary.new)
      @env = env
      @tracker = tracker
      @git = git
      @travel_request = travel_request
      @configuration = configuration
      @failure_boundary = failure_boundary
    end

    def to_h
      selection = ref_selection
      active_ref = selection&.accepted? ? selection.sha : nil
      active_branch = active_ref ? active_branch_for(selection) : nil
      current_branch = safe_git_value(:current_branch)
      current_commit = safe_git_value(:current_commit)
      references = safe_references
      selected_reference = select_reference(references, active_branch || current_branch)
      commits = safe_commits(selected_reference)
      selected_commit = select_commit(commits, active_ref || current_commit)

      {
        current_branch: current_branch,
        current_commit: current_commit,
        active_ref: active_ref,
        active_branch: active_branch,
        authenticity_token: authenticity_token,
        commits: commits,
        engine_mount: RailsWayback::EngineMount.path,
        diff_info: active_ref ? diff_info(active_ref) : nil,
        csp_nonce: content_security_policy_nonce,
        ref_error: selection&.rejected? ? selection.message : nil,
        references: references,
        return_to: travel_request.return_to,
        selected_branch: selected_reference&.full_name.to_s,
        selected_commit: selected_commit&.sha.to_s
      }
    end

    private

    attr_reader :configuration, :env, :failure_boundary, :git, :tracker, :travel_request

    def safe_git_value(method)
      capture("load toolbar #{method.to_s.tr("_", " ")}", fallback: "", git_only: true) do
        git.public_send(method)
      end
    end

    def safe_references
      capture("load toolbar refs", fallback: [], git_only: true) { git.references }
    end

    def safe_commits(reference)
      return [] unless reference

      capture("load toolbar commits", fallback: [], git_only: true) do
        git.commits(reference.full_name)
      end
    end

    def select_reference(references, selector)
      GitReference.find(references, selector) || references.first
    end

    def select_commit(commits, sha)
      commits.find { |commit| commit.sha == sha } || commits.first
    end

    def ref_selection
      return env[RailsWayback::RefPolicy::ENV_KEY] if env.key?(RailsWayback::RefPolicy::ENV_KEY)
      return unless travel_request.ref

      policy = RailsWayback::RefPolicy.new(configuration: configuration, git: git)
      policy.authorize(travel_request.ref).tap do |selection|
        env[RailsWayback::RefPolicy::ENV_KEY] = selection
      end
    end

    def active_branch_for(selection)
      explicit_ref = trusted_ref_for(travel_request.branch, selection.trusted_refs)
      return GitReference.label_for(explicit_ref) if explicit_ref

      capture("resolve toolbar active ref", fallback: nil, git_only: true) do
        inferred = git.resolve_branch_for(selection.sha)
        next inferred if inferred && selection.trusted_refs.include?("refs/heads/#{inferred}")

        GitReference.label_for(selection.trusted_refs.first)
      end
    end

    def trusted_ref_for(selector, trusted_refs)
      return if selector.to_s.empty?

      GitReference.find(trusted_refs, selector)
    end

    def diff_info(ref)
      capture("build toolbar diff info", fallback: nil) do
        changed_files = git.diff_paths(ref, paths: tracked_paths)
        rendered = RailsWayback::RenderProvenance.paths_by_origin(
          tracker.entries,
          configuration: configuration
        )
        assets = RailsWayback::AssetProvenance.paths_by_origin(tracker.entries)

        {
          changed_files: changed_files,
          rendered_from_ref: rendered[:historical],
          rendered_from_current: rendered[:current],
          historical_assets: assets[:historical],
          current_asset_fallbacks: assets[:current],
          preview_mode: preview_mode(rendered[:historical], rendered[:current]),
          matched: changed_files & rendered[:historical]
        }
      end
    end

    def tracked_paths
      (configuration.view_paths + configuration.asset_paths).uniq
    end

    def preview_mode(historical, current)
      return :mixed if historical.any? && current.any?
      return :historical if historical.any?
      return :current_fallback if current.any?

      :unknown
    end

    def content_security_policy_nonce
      capture("read content security policy nonce", fallback: nil) do
        request = ActionDispatch::Request.new(env)
        request.content_security_policy_nonce if request.respond_to?(:content_security_policy_nonce)
      end
    end

    def authenticity_token
      capture("build toolbar authenticity token", fallback: "") do
        controller = env["action_controller.instance"]
        next "" unless controller

        controller.send(:form_authenticity_token).to_s
      end
    end

    def capture(context, fallback:, git_only: false, &)
      errors = git_only ? [RailsWayback::Git::GitError] : [StandardError]
      failure_boundary.capture(context, fallback: fallback, rescue_errors: errors, &).value
    end
  end
end
