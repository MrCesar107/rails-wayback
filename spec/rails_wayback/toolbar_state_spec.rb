# frozen_string_literal: true

require "rails_wayback/toolbar_state"

RSpec.describe RailsWayback::ToolbarState do
  def reference
    RailsWayback::Git::Reference.new(
      full_name: "refs/heads/main", name: "main", kind: :branch, label: "main"
    )
  end

  def commit
    RailsWayback::Git::Commit.new(
      sha: "b" * 40, short_sha: "bbbbbbb", subject: "Current work"
    )
  end

  it "builds renderer attributes from the request, policy, Git, and render tracker" do
    sha = "a" * 40
    selection = RailsWayback::RefPolicy::Result.new(
      input: sha,
      sha: sha,
      trusted_refs: ["refs/heads/main"].freeze
    )
    env = {
      RailsWayback::RefPolicy::ENV_KEY => selection,
      "PATH_INFO" => "/letters",
      "QUERY_STRING" => ""
    }
    git = instance_double(
      RailsWayback::Git,
      current_branch: "main",
      current_commit: "b" * 40,
      diff_paths: ["app/views/letters/index.html.erb"],
      references: [reference],
      commits: [commit]
    )
    travel_request = instance_double(
      RailsWayback::TravelRequest,
      ref: sha,
      branch: "main",
      return_to: "/letters"
    )
    tracker = RailsWayback::RenderTracker.new

    attributes = described_class.new(
      env: env,
      git: git,
      tracker: tracker,
      travel_request: travel_request
    ).to_h

    expect(attributes).to include(
      current_branch: "main",
      current_commit: "b" * 40,
      active_ref: sha,
      active_branch: "main",
      authenticity_token: "",
      return_to: "/letters",
      ref_error: nil
    )
    expect(attributes.fetch(:references).map(&:full_name)).to eq(["refs/heads/main"])
    expect(attributes.fetch(:commits).map(&:sha)).to eq(["b" * 40])
    expect(attributes.fetch(:diff_info)).to include(
      changed_files: ["app/views/letters/index.html.erb"],
      rendered_from_ref: [],
      rendered_from_current: [],
      matched: []
    )
  end

  it "reports rejected selections without producing historical state" do
    selection = RailsWayback::RefPolicy::Result.new(
      input: "HEAD~1",
      trusted_refs: [].freeze,
      reason: :invalid_format,
      message: "Rejected travel ref"
    )
    env = { RailsWayback::RefPolicy::ENV_KEY => selection, "PATH_INFO" => "/letters" }
    git = instance_double(
      RailsWayback::Git,
      current_branch: "main",
      current_commit: "current",
      references: [],
      commits: []
    )
    travel_request = instance_double(
      RailsWayback::TravelRequest,
      ref: "HEAD~1",
      branch: nil,
      return_to: "/letters"
    )

    attributes = described_class.new(
      env: env,
      git: git,
      tracker: RailsWayback::RenderTracker.new,
      travel_request: travel_request
    ).to_h

    expect(attributes).to include(
      active_ref: nil,
      active_branch: nil,
      diff_info: nil,
      ref_error: "Rejected travel ref"
    )
  end

  it "fails open for expected Git errors and records the structured boundary" do
    logger = instance_double(Logger, warn: nil)
    boundary = RailsWayback::FailureBoundary.new(logger: logger)
    git = instance_double(RailsWayback::Git)
    allow(git).to receive(:current_branch).and_raise(RailsWayback::Git::GitError, "no branch")
    allow(git).to receive(:current_commit).and_return("b" * 40)
    allow(git).to receive(:references).and_raise(RailsWayback::Git::GitError, "no refs")
    travel_request = instance_double(RailsWayback::TravelRequest, ref: nil, return_to: "/letters")

    attributes = described_class.new(
      env: { "PATH_INFO" => "/letters" },
      git: git,
      tracker: RailsWayback::RenderTracker.new,
      travel_request: travel_request,
      failure_boundary: boundary
    ).to_h

    expect(attributes).to include(current_branch: "", current_commit: "b" * 40, references: [], commits: [])
    expect(logger).to have_received(:warn).with(
      "[rails-wayback] load toolbar current branch failed: RailsWayback::Git::GitError: no branch"
    )
    expect(logger).to have_received(:warn).with(
      "[rails-wayback] load toolbar refs failed: RailsWayback::Git::GitError: no refs"
    )
  end

  it "does not hide unexpected errors inside a Git operation" do
    git = instance_double(RailsWayback::Git)
    allow(git).to receive(:current_branch).and_raise(ArgumentError, "bug")
    travel_request = instance_double(RailsWayback::TravelRequest, ref: nil)

    state = described_class.new(
      env: {},
      git: git,
      tracker: RailsWayback::RenderTracker.new,
      travel_request: travel_request
    )

    expect { state.to_h }.to raise_error(ArgumentError, "bug")
  end
end
