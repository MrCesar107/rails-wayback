# frozen_string_literal: true

require "uri"
require_relative "../../support/engine_request_app"

RSpec.describe RailsWayback::TravelsController do
  let(:request) { EngineRequestApp.request }
  let(:git) { instance_double(RailsWayback::Git) }

  before do
    allow(RailsWayback).to receive(:enabled?).and_return(true)
    allow(RailsWayback::Git).to receive(:new).and_return(git)
  end

  describe "#create" do
    it "authorizes travel, canonicalizes the branch cookie, and redirects locally" do
      sha = "c" * 40
      allow(git).to receive(:resolve_ref).with(sha).and_return(sha)
      allow(git).to receive(:refs_containing).with(sha).and_return(["refs/tags/preview-v1"])
      RailsWayback.configuration.trusted_ref_patterns = ["refs/tags/*"]

      response = request.post(
        "/rails-wayback/travel",
        params: { ref: sha, branch: "tag:preview-v1", confirmed: "true", return_to: "/articles?page=2" }
      )
      cookies = Array(response.headers["set-cookie"]).join("\n")

      expect(response.status).to eq(302)
      expect(URI.parse(response.headers.fetch("location")).request_uri).to eq("/articles?page=2")
      expect(cookies).to include("rails_wayback_ref=#{sha}", "rails_wayback_branch=refs%2Ftags%2Fpreview-v1")
      expect(cookies).to include("httponly", "samesite=lax")
    end

    it "rejects unconfirmed travel without resolving or storing a ref" do
      allow(git).to receive(:resolve_ref)

      response = request.post(
        "/rails-wayback/travel",
        params: { ref: "d" * 40, return_to: "/articles" }
      )

      expect(response.status).to eq(422)
      expect(response.body).to include("Confirm that you trust")
      expect(response.headers["set-cookie"].to_s).to be_empty
      expect(git).not_to have_received(:resolve_ref)
    end
  end

  describe "#destroy" do
    it "clears both travel cookies and rejects external redirects" do
      response = request.request(
        "DELETE",
        "/rails-wayback/travel?return_to=https%3A%2F%2Fevil.example%2Fescape",
        "HTTP_COOKIE" => "rails_wayback_ref=old; rails_wayback_branch=refs%2Fheads%2Fmain"
      )
      cookies = Array(response.headers["set-cookie"]).join("\n")
      location = URI.parse(response.headers.fetch("location"))

      expect(response.status).to eq(302)
      expect(location.path).to eq("/")
      expect(cookies.scan("max-age=0").size).to be >= 2
      expect(cookies).to include("rails_wayback_ref=", "rails_wayback_branch=")
    end
  end
end
