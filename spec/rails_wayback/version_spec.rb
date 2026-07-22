# frozen_string_literal: true

RSpec.describe RailsWayback do
  it "exposes a semver-ish version" do
    expect(RailsWayback::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
