# frozen_string_literal: true

RSpec.describe "RailsWayback environment restrictions" do
  it "allows development and test but rejects production by default" do
    allow(RailsWayback).to receive(:current_environment).and_return("development")
    expect(RailsWayback.environment_allowed?).to be(true)

    allow(RailsWayback).to receive(:current_environment).and_return("test")
    expect(RailsWayback.environment_allowed?).to be(true)

    allow(RailsWayback).to receive(:current_environment).and_return("production")
    expect(RailsWayback.environment_allowed?).to be(false)
  end

  it "refuses to enable in a disallowed environment" do
    SpecSupport.with_tmp_root do |root|
      allow(RailsWayback).to receive(:current_environment).and_return("production")

      expect { RailsWayback.enable! }
        .to raise_error(RailsWayback::DisabledError, /production.*not allowed/)
      expect(root.join("tmp/rails_wayback/enabled")).not_to exist
    end
  end

  it "ignores an existing toggle file in a disallowed environment" do
    SpecSupport.with_tmp_root do
      RailsWayback.toggle.enable!
      allow(RailsWayback).to receive(:current_environment).and_return("production")

      expect(RailsWayback.toggle.enabled?).to be(true)
      expect(RailsWayback.enabled?).to be(false)
    end
  end

  it "supports an explicit environment opt-in" do
    SpecSupport.with_tmp_root do
      RailsWayback.configuration.allowed_environments << "staging"
      allow(RailsWayback).to receive(:current_environment).and_return("staging")

      expect { RailsWayback.enable! }.not_to raise_error
      expect(RailsWayback.enabled?).to be(true)
    end
  end
end
