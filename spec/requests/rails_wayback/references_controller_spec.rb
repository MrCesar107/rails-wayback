# frozen_string_literal: true

require "json"
require_relative "../../support/engine_request_app"

RSpec.describe RailsWayback::ReferencesController do
  describe "#index" do
    let(:request) { EngineRequestApp.request }
    let(:git) { instance_double(RailsWayback::Git) }

    before do
      allow(RailsWayback).to receive(:enabled?).and_return(true)
      allow(RailsWayback::Git).to receive(:new).and_return(git)
    end

    it "serializes current state and canonical reference metadata" do
      reference = RailsWayback::GitReference.parse("refs/tags/preview-v1")
      allow(git).to receive_messages(
        current_branch: "main",
        current_commit: "a" * 40,
        references: [reference]
      )

      response = request.get("/rails-wayback/references")
      payload = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(payload).to include("current_branch" => "main", "current_commit" => "a" * 40, "errors" => [])
      expect(payload.fetch("refs")).to contain_exactly(
        "full_name" => "refs/tags/preview-v1",
        "name" => "preview-v1",
        "type" => "tag",
        "label" => "tag:preview-v1"
      )
    end

    it "fails open with structured Git error summaries" do
      allow(git).to receive(:current_branch).and_raise(RailsWayback::Git::GitError, "branch unavailable")
      allow(git).to receive(:current_commit).and_return("a" * 40)
      allow(git).to receive(:references).and_raise(RailsWayback::Git::GitError, "refs unavailable")

      response = request.get("/rails-wayback/references")
      payload = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(payload).to include("current_branch" => nil, "current_commit" => "a" * 40, "refs" => [])
      expect(payload.fetch("errors")).to contain_exactly(
        "RailsWayback::Git::GitError: branch unavailable",
        "RailsWayback::Git::GitError: refs unavailable"
      )
    end
  end
end
