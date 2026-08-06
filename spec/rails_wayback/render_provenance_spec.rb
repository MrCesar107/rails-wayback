# frozen_string_literal: true

RSpec.describe RailsWayback::RenderProvenance do
  it "classifies historical, current, and unrelated render identifiers" do
    SpecSupport.with_tmp_root do |root|
      config = RailsWayback.configuration
      historical = config.refs_cache_path.join("abc123/app/views/letters/show.html.erb")
      current = root.join("app/views/layouts/application.html.erb")

      expect(described_class.origin_for(historical.to_s)).to eq(:historical)
      expect(described_class.origin_for(current.to_s)).to eq(:current)
      expect(described_class.origin_for("/gems/example/app/views/widget.html.erb")).to eq(:other)
      expect(described_class.origin_for("integration/item")).to eq(:other)
    end
  end

  it "uses the configured refs root instead of a hardcoded tmp path" do
    SpecSupport.with_tmp_root do |root|
      custom_refs = root.join("custom/cache/refs")
      RailsWayback.configuration.cache_root = root.join("custom/cache")
      identifier = custom_refs.join("def456/app/views/home/index.html.erb")

      expect(described_class.origin_for(identifier.to_s)).to eq(:historical)
    end
  end

  it "returns unique application-relative paths grouped by origin" do
    SpecSupport.with_tmp_root do |root|
      config = RailsWayback.configuration
      refs_root = config.refs_cache_path
      historical = refs_root.join("abc123/app/views/letters/show.html.erb").to_s
      current = root.join("app/views/layouts/application.html.erb").to_s
      entries = [
        { event: "render_template.action_view", identifier: historical },
        { event: "render_partial.action_view", identifier: historical },
        { event: "render_layout.action_view", identifier: current },
        { event: "render_partial.action_view", identifier: "/gems/example/app/views/ignored.html.erb" }
      ]

      expect(described_class.paths_by_origin(entries)).to eq(
        historical: ["app/views/letters/show.html.erb"],
        current: ["app/views/layouts/application.html.erb"]
      )
    end
  end
end
