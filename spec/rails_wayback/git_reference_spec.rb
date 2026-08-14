# frozen_string_literal: true

require "rails_wayback/git_reference"

RSpec.describe RailsWayback::GitReference do
  describe ".parse" do
    it "derives canonical names, kinds, and labels from supported refs" do
      branch = described_class.parse("refs/heads/feature/search")
      remote = described_class.parse("refs/remotes/origin/review/topic")
      tag = described_class.parse("refs/tags/preview-v1")

      expect(branch.to_h).to eq(
        full_name: "refs/heads/feature/search",
        name: "feature/search",
        kind: :branch,
        label: "feature/search"
      )
      expect(remote.to_h).to include(name: "origin/review/topic", kind: :remote)
      expect(tag.to_h).to include(name: "preview-v1", kind: :tag, label: "tag:preview-v1")
    end

    it "returns nil for names outside the supported Git ref namespaces" do
      expect(described_class.parse("HEAD")).to be_nil
      expect(described_class.parse("refs/notes/reviewed")).to be_nil
    end
  end

  describe ".find" do
    let(:references) do
      [
        described_class.parse("refs/heads/release"),
        described_class.parse("refs/remotes/release"),
        described_class.parse("refs/tags/release")
      ]
    end

    it "matches canonical names, short names, and display labels" do
      expect(described_class.find(references, "refs/remotes/release").kind).to eq(:remote)
      expect(described_class.find(references, "release").kind).to eq(:branch)
      expect(described_class.find(references, "tag:release").kind).to eq(:tag)
    end

    it "also canonicalizes matching string refs without changing the collection values" do
      refs = references.map(&:full_name)

      expect(described_class.find(refs, "tag:release")).to eq("refs/tags/release")
      expect(described_class.find(refs, "missing")).to be_nil
    end
  end
end
