# frozen_string_literal: true

RSpec.describe RailsWayback::RenderContext do
  it "scopes a tracker and restores the previous context" do
    outer = RailsWayback::RenderTracker.new
    inner = RailsWayback::RenderTracker.new

    described_class.with(outer) do
      expect(described_class.current).to equal(outer)

      described_class.with(inner) do
        expect(described_class.current).to equal(inner)
      end

      expect(described_class.current).to equal(outer)
    end

    expect(described_class.current).to be_nil
  end

  it "restores the context when the scoped work raises" do
    tracker = RailsWayback::RenderTracker.new

    expect do
      described_class.with(tracker) { raise "render failed" }
    end.to raise_error("render failed")

    expect(described_class.current).to be_nil
  end

  it "shares the request tracker with child fibers" do
    tracker = RailsWayback::RenderTracker.new

    described_class.with(tracker) do
      Fiber.new do
        described_class.current.record(event: "partial", identifier: "/app/views/_child.html.erb")
      end.resume
    end

    expect(tracker.entries).to contain_exactly(
      event: "partial",
      identifier: "/app/views/_child.html.erb"
    )
  end

  it "keeps sibling request fibers isolated" do
    first_tracker = RailsWayback::RenderTracker.new
    second_tracker = RailsWayback::RenderTracker.new

    first_fiber = recording_fiber(first_tracker, "first")
    second_fiber = recording_fiber(second_tracker, "second")

    first_fiber.resume
    second_fiber.resume
    first_fiber.resume
    second_fiber.resume

    expect(first_tracker.entries).to eq([{ event: "template", identifier: "first" }])
    expect(second_tracker.entries).to eq([{ event: "template", identifier: "second" }])
    expect(described_class.current).to be_nil
  end

  def recording_fiber(tracker, identifier)
    Fiber.new do
      described_class.with(tracker) do
        Fiber.yield
        described_class.current.record(event: "template", identifier: identifier)
      end
    end
  end
end
