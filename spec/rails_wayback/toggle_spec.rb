# frozen_string_literal: true

RSpec.describe RailsWayback::Toggle do
  it "flips between enabled and disabled and persists to the toggle file" do
    SpecSupport.with_tmp_root do |root|
      toggle = described_class.new

      expect(toggle.status).to eq(:off)
      expect(toggle.enabled?).to be(false)

      toggle.enable!
      expect(toggle.enabled?).to be(true)
      expect(toggle.status).to eq(:on)
      expect(root.join("tmp", "rails_wayback", "enabled")).to exist

      toggle.disable!
      expect(toggle.enabled?).to be(false)
      expect(root.join("tmp", "rails_wayback", "enabled")).not_to exist
    end
  end

  it "touches config/routes.rb when it exists so Rails reloads routes" do
    SpecSupport.with_tmp_root do |root|
      routes = root.join("config", "routes.rb")
      FileUtils.mkdir_p(routes.dirname)
      File.write(routes, "# routes")
      before = routes.mtime

      sleep 1.01
      described_class.new.enable!
      expect(routes.mtime).to be > before
    end
  end
end
