# frozen_string_literal: true

require "json"
require_relative "../../support/engine_request_app"

RSpec.describe RailsWayback::CommitsController do
  describe "#index" do
    let(:request) { EngineRequestApp.request }
    let(:git) { instance_double(RailsWayback::Git) }

    before do
      allow(RailsWayback).to receive(:enabled?).and_return(true)
      allow(RailsWayback::Git).to receive(:new).and_return(git)
    end

    it "resolves a selector and serializes its commits" do
      reference = RailsWayback::GitReference.parse("refs/heads/feature/search")
      commit = RailsWayback::Git::Commit.new(
        sha: "b" * 40,
        short_sha: "bbbbbbb",
        subject: "Search refactor",
        author: "Developer",
        date: "2026-08-13T10:00:00-06:00"
      )
      allow(git).to receive(:reference).with("feature/search").and_return(reference)
      allow(git).to receive(:commits).with(reference.full_name).and_return([commit])

      response = request.get("/rails-wayback/commits?reference=feature%2Fsearch")
      payload = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(payload).to include("branch" => "feature/search", "error" => nil)
      expect(payload.fetch("ref")).to include("full_name" => reference.full_name, "label" => reference.label)
      expect(payload.fetch("commits").first).to include("sha" => "b" * 40, "subject" => "Search refactor")
    end

    it "returns an empty collection when trusted commit discovery fails" do
      allow(git).to receive(:reference).and_raise(RailsWayback::Git::GitError, "not trusted")

      response = request.get("/rails-wayback/commits?reference=missing")
      payload = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(payload).to include(
        "branch" => "missing",
        "ref" => nil,
        "commits" => [],
        "error" => "RailsWayback::Git::GitError: not trusted"
      )
    end
  end
end
