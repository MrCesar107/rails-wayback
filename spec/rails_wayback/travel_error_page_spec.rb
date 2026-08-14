# frozen_string_literal: true

require "rails_wayback/travel_error_page"

RSpec.describe RailsWayback::TravelErrorPage do
  it "renders escaped diagnostics and a reset action without host templates" do
    html = described_class.new(
      authenticity_token: %(<token>),
      branch: %(<main>"branch"),
      error: ArgumentError.new(%(<script>alert("unsafe")</script>)),
      ref: "abcdef1234567890",
      return_to: %(/letters?<unsafe>),
      travel_url: "/rails-wayback/travel"
    ).render

    expect(html).to include(
      "Historical preview failed",
      "&lt;main&gt;&quot;branch&quot;",
      "abcdef1234567890",
      "ArgumentError",
      "&lt;script&gt;alert(&quot;unsafe&quot;)&lt;/script&gt;",
      'action="/rails-wayback/travel"',
      'name="_method" value="delete"',
      'name="authenticity_token" value="&lt;token&gt;"',
      'name="return_to" value="/letters?&lt;unsafe&gt;"'
    )
    expect(html).not_to include("<script>", "<main>")
  end
end
