# frozen_string_literal: true

require "stringio"
require "rails_wayback/cli"

RSpec.describe RailsWayback::CLI do
  it "prints the current status" do
    SpecSupport.with_tmp_root do
      out = StringIO.new
      described_class.start(["status"], stdout: out, stderr: StringIO.new)
      expect(out.string).to match(/rails-wayback: (on|off)/)
    end
  end

  it "enables and disables the engine" do
    SpecSupport.with_tmp_root do
      out = StringIO.new
      described_class.start(["on"], stdout: out, stderr: StringIO.new)
      expect(RailsWayback.enabled?).to be(true)

      described_class.start(["off"], stdout: out, stderr: StringIO.new)
      expect(RailsWayback.enabled?).to be(false)
    end
  end

  it "handles unknown commands by returning an error and showing help" do
    SpecSupport.with_tmp_root do
      out = StringIO.new
      err = StringIO.new
      status = described_class.start(["nope"], stdout: out, stderr: err)
      expect(status).to eq(1)
      expect(err.string).to include("Unknown command")
      expect(out.string).to include("Usage: rails-wayback")
    end
  end

  it "cleans the ref cache" do
    SpecSupport.with_tmp_root do |root|
      FileUtils.mkdir_p(root.join("tmp/rails_wayback/refs/abc"))
      described_class.start(["clean"], stdout: StringIO.new, stderr: StringIO.new)
      expect(root.join("tmp/rails_wayback/refs/abc")).not_to exist
    end
  end
end
