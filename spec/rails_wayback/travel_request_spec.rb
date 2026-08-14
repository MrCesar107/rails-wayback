# frozen_string_literal: true

require "action_dispatch"
require "rails_wayback/travel_request"

RSpec.describe RailsWayback::TravelRequest do
  it "uses ActionDispatch request parameters before cookies" do
    env = { "PATH_INFO" => "/letters" }
    request = instance_double(
      ActionDispatch::Request,
      query_parameters: {
        "_wayback_ref" => "query-ref",
        "_wayback_branch" => "query-branch"
      },
      cookies: {
        "rails_wayback_ref" => "cookie-ref",
        "rails_wayback_branch" => "cookie-branch"
      }
    )
    allow(ActionDispatch::Request).to receive(:new).with(env).and_return(request)

    travel_request = described_class.new(env)

    expect(travel_request.ref).to eq("query-ref")
    expect(travel_request.branch).to eq("query-branch")
  end

  it "falls back to Rails-parsed cookies and normalizes blank values" do
    env = { "PATH_INFO" => "/letters" }
    request = instance_double(
      ActionDispatch::Request,
      query_parameters: { "_wayback_ref" => "", "_wayback_branch" => nil },
      cookies: {
        "rails_wayback_ref" => "cookie-ref",
        "rails_wayback_branch" => "cookie-branch"
      }
    )
    allow(ActionDispatch::Request).to receive(:new).with(env).and_return(request)

    travel_request = described_class.new(env)

    expect(travel_request.ref).to eq("cookie-ref")
    expect(travel_request.branch).to eq("cookie-branch")
  end

  it "builds a local return path without wayback query parameters" do
    env = { "PATH_INFO" => "/letters" }
    request = instance_double(
      ActionDispatch::Request,
      path: "/letters",
      query_parameters: {
        "tab" => "preview",
        "_wayback_ref" => "ref",
        "_wayback_branch" => "main"
      },
      cookies: {}
    )
    allow(ActionDispatch::Request).to receive(:new).with(env).and_return(request)

    expect(described_class.new(env).return_to).to eq("/letters?tab=preview")
  end
end
