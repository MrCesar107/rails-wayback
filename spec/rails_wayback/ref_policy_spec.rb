# frozen_string_literal: true

RSpec.describe RailsWayback::RefPolicy do
  let(:sha) { "a" * 40 }
  let(:git) { instance_spy(RailsWayback::Git) }
  let(:configuration) { RailsWayback::Configuration.new }
  let(:policy) { described_class.new(configuration: configuration, git: git) }

  it "accepts a full commit SHA reachable from a trusted local branch" do
    allow(git).to receive(:resolve_ref).with(sha).and_return(sha)
    allow(git).to receive(:refs_containing).with(sha).and_return(
      ["refs/remotes/origin/review", "refs/heads/feature/nested", "refs/heads/main"]
    )

    result = policy.authorize(sha)

    expect(result).to be_accepted
    expect(result.sha).to eq(sha)
    expect(result.trusted_refs).to eq(["refs/heads/feature/nested", "refs/heads/main"])
  end

  it "rejects revision expressions before asking Git to resolve them" do
    result = policy.authorize("HEAD~1")

    expect(result).to be_rejected
    expect(result.reason).to eq(:invalid_format)
    expect(result.message).to include("full 40- or 64-character commit SHA")
    expect(git).not_to have_received(:resolve_ref)
  end

  it "rejects a syntactically valid SHA that does not exist" do
    allow(git).to receive(:resolve_ref).with(sha).and_raise(RailsWayback::RefNotFoundError)

    result = policy.authorize(sha)

    expect(result).to be_rejected
    expect(result.reason).to eq(:unknown_ref)
  end

  it "rejects commits reachable only from remote refs by default" do
    allow(git).to receive(:resolve_ref).with(sha).and_return(sha)
    allow(git).to receive(:refs_containing).with(sha).and_return(["refs/remotes/origin/untrusted"])

    result = policy.authorize(sha)

    expect(result).to be_rejected
    expect(result.reason).to eq(:untrusted_ref)
  end

  it "supports explicit trusted ref patterns" do
    configuration.trusted_ref_patterns = ["refs/remotes/origin/review/*"]
    allow(git).to receive(:resolve_ref).with(sha).and_return(sha)
    allow(git).to receive(:refs_containing).with(sha).and_return(
      ["refs/remotes/origin/review/contributor"]
    )

    result = policy.authorize(sha)

    expect(result).to be_accepted
    expect(result.trusted_refs).to eq(["refs/remotes/origin/review/contributor"])
  end
end
