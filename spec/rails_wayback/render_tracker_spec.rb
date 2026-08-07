# frozen_string_literal: true

RSpec.describe RailsWayback::RenderTracker do
  it "records immutable entries and returns independent snapshots" do
    tracker = described_class.new

    expect(tracker.record(event: :partial, identifier: "/app/views/_item.html.erb")).to be(true)

    snapshot = tracker.entries
    snapshot.clear

    expect(tracker.entries).to eq(
      [{ event: "partial", identifier: "/app/views/_item.html.erb" }]
    )
    expect(tracker.entries.first).to be_frozen
  end

  it "rejects new entries after it is closed" do
    tracker = described_class.new
    tracker.record(event: "template", identifier: "/app/views/index.html.erb")

    tracker.close

    expect(tracker).to be_closed
    expect(tracker.record(event: "late", identifier: "/app/views/late.html.erb")).to be(false)
    expect(tracker.entries.size).to eq(1)
  end

  it "serializes writers when a tracker is explicitly shared across threads" do
    tracker = described_class.new
    threads = 4.times.map do |thread_index|
      Thread.new do
        25.times do |entry_index|
          tracker.record(event: "partial", identifier: "#{thread_index}/#{entry_index}")
        end
      end
    end

    threads.each(&:join)

    expect(tracker.entries.size).to eq(100)
  end
end
