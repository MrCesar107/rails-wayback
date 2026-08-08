# frozen_string_literal: true

RSpec.describe RailsWayback::AssetProvenance do
  it "groups unique historical assets and current fallbacks" do
    entries = [
      { event: "rails_wayback.asset.historical", identifier: "public/theme.css" },
      { event: "rails_wayback.asset.historical", identifier: "public/theme.css" },
      { event: "rails_wayback.asset.current", identifier: "missing.css" },
      { event: "render_template.action_view", identifier: "/app/views/show.html.erb" }
    ]

    expect(described_class.paths_by_origin(entries)).to eq(
      historical: ["public/theme.css"],
      current: ["missing.css"]
    )
  end

  it "records asset resolution on the current request tracker" do
    tracker = RailsWayback::RenderTracker.new

    RailsWayback::RenderContext.with(tracker) do
      described_class.record(origin: :historical, identifier: "public/logo.svg")
      described_class.record(origin: :external, identifier: "https://example.test/logo.svg")
    end

    expect(tracker.entries).to eq(
      [{ event: "rails_wayback.asset.historical", identifier: "public/logo.svg" }]
    )
  end
end
