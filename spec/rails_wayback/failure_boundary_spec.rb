# frozen_string_literal: true

require "rails_wayback/failure_boundary"

RSpec.describe RailsWayback::FailureBoundary do
  subject(:boundary) { described_class.new(logger: logger) }

  let(:logger) { instance_double(Logger, warn: nil) }

  it "returns successful values without logging" do
    result = boundary.capture("load toolbar refs", fallback: []) { %w[main release] }

    expect(result).to be_success
    expect(result.value).to eq(%w[main release])
    expect(result.failure).to be_nil
    expect(logger).not_to have_received(:warn)
  end

  it "returns a structured failure, logs it, and exposes the explicit fallback" do
    result = boundary.capture("load toolbar refs", fallback: []) { raise RailsWayback::Git::GitError, "offline" }

    expect(result).to be_failure
    expect(result.value).to eq([])
    expect(result.failure).to have_attributes(
      context: "load toolbar refs",
      exception_class: "RailsWayback::Git::GitError",
      message: "offline"
    )
    expect(logger).to have_received(:warn).with(
      "[rails-wayback] load toolbar refs failed: RailsWayback::Git::GitError: offline"
    )
  end

  it "only catches the exception classes assigned to that boundary" do
    expect do
      boundary.capture("load toolbar refs", fallback: [], rescue_errors: [RailsWayback::Git::GitError]) do
        raise ArgumentError, "programming error"
      end
    end.to raise_error(ArgumentError, "programming error")
  end
end
