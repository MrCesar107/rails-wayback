# frozen_string_literal: true

require "json"
require "open3"
require "rails_wayback/bar_renderer"

RSpec.describe RailsWayback::BarRenderer do
  let(:search_module) { File.expand_path("../../lib/rails_wayback/bar_search.js", __dir__) }

  def run_search(method, items:, query:, selected: nil)
    script = <<~JAVASCRIPT
      const search = require(process.argv[1]);
      const input = JSON.parse(process.argv[2]);
      const result = search[process.argv[3]](input.items, input.query, input.selected);
      process.stdout.write(JSON.stringify(result));
    JAVASCRIPT
    input = JSON.generate(items: items, query: query, selected: selected)
    stdout, stderr, status = Open3.capture3("node", "-e", script, search_module, input, method.to_s)
    expect(status).to be_success, stderr

    JSON.parse(stdout)
  rescue Errno::ENOENT
    skip "Node.js is required to exercise the packaged toolbar search module"
  end

  it "filters refs across labels, names, full refs, and types while preserving selection" do
    references = [
      { full_name: "refs/heads/main", name: "main", label: "main", type: "branch" },
      {
        full_name: "refs/remotes/origin/feature/search",
        name: "origin/feature/search",
        label: "origin/feature/search",
        type: "remote"
      },
      { full_name: "refs/tags/preview-v1", name: "preview-v1", label: "tag:preview-v1", type: "tag" }
    ]

    result = run_search(
      :searchReferences,
      items: references,
      query: "  FEATURE  ",
      selected: "refs/heads/main"
    )

    expect(result.fetch("matches").map { |item| item.fetch("full_name") })
      .to eq(["refs/remotes/origin/feature/search"])
    expect(result.fetch("visible").map { |item| item.fetch("full_name") })
      .to eq(["refs/heads/main", "refs/remotes/origin/feature/search"])

    tag_result = run_search(:searchReferences, items: references, query: "TAG", selected: nil)
    expect(tag_result.fetch("matches").map { |item| item.fetch("full_name") })
      .to eq(["refs/tags/preview-v1"])
  end

  it "filters commits by full or short SHA, subject, author, and date" do
    commits = [
      {
        sha: "a" * 40,
        short_sha: "aaaaaaa",
        subject: "Add searchable refs",
        author: "Alice Example",
        date: "2026-08-08T10:00:00Z"
      },
      {
        sha: ["deadbeef", "b" * 32].join,
        short_sha: "deadbee",
        subject: "Document cache behavior",
        author: "Bob Example",
        date: "2026-08-07T09:00:00Z"
      }
    ]

    author_result = run_search(:searchCommits, items: commits, query: "ALICE", selected: nil)
    expect(author_result.fetch("matches").map { |item| item.fetch("short_sha") }).to eq(["aaaaaaa"])

    sha_result = run_search(:searchCommits, items: commits, query: "deadbeef", selected: "a" * 40)
    expect(sha_result.fetch("matches").map { |item| item.fetch("short_sha") }).to eq(["deadbee"])
    expect(sha_result.fetch("visible").map { |item| item.fetch("short_sha") })
      .to eq(%w[aaaaaaa deadbee])

    date_result = run_search(:searchCommits, items: commits, query: "2026-08-07", selected: nil)
    expect(date_result.fetch("matches").map { |item| item.fetch("short_sha") }).to eq(["deadbee"])
  end

  it "returns all loaded items for an empty query and no items for an unmatched query" do
    references = [
      { full_name: "refs/heads/main", name: "main", label: "main", type: "branch" },
      { full_name: "refs/heads/release", name: "release", label: "release", type: "branch" }
    ]

    all = run_search(:searchReferences, items: references, query: "  ", selected: "refs/heads/main")
    expect(all.fetch("matches").size).to eq(2)
    expect(all.fetch("visible").size).to eq(2)

    none = run_search(:searchReferences, items: references, query: "missing", selected: nil)
    expect(none).to eq("matches" => [], "visible" => [])
  end
end
