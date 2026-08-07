# frozen_string_literal: true

require "rails_wayback/bar_renderer"

RSpec.describe RailsWayback::BarRenderer do
  it "renders the bar HTML with branch, commit and active ref data attributes" do
    html = described_class.new(
      current_branch: "main",
      current_commit: "abc1234",
      active_ref: "def5678",
      active_branch: "master",
      engine_mount: "/rails-wayback"
    ).render

    expect(html).to include('id="rails-wayback-bar"')
    expect(html).to include('data-branch="main"')
    expect(html).to include('data-commit="abc1234"')
    expect(html).to include('data-active-ref="def5678"')
    expect(html).to include('data-active-branch="master"')
    expect(html).to include('data-mount="/rails-wayback"')
    expect(html).to include("data-rw-travel")
    expect(html).to include("data-rw-reset")
    expect(html).to include(%(href="/rails-wayback/assets/bar.css?v=#{RailsWayback::VERSION}"))
    expect(html).to include(%(src="/rails-wayback/assets/bar.js?v=#{RailsWayback::VERSION}"))
    expect(html).not_to include("<style")
    expect(html).not_to include("(function ()")
  end

  it "normalizes custom mounts and escapes a CSP nonce on both asset tags" do
    html = described_class.new(
      current_branch: "main",
      current_commit: "abc1234",
      engine_mount: "/developer/wayback/",
      csp_nonce: %(nonce"><script>)
    ).render

    expect(html).to include(%(href="/developer/wayback/assets/bar.css?v=#{RailsWayback::VERSION}"))
    expect(html).to include(%(src="/developer/wayback/assets/bar.js?v=#{RailsWayback::VERSION}"))
    expect(html.scan(%(nonce="nonce&quot;&gt;&lt;script&gt;")).size).to eq(2)
    expect(html).not_to include(%(nonce="nonce"><script>"))
  end

  it "labels the dropdowns as 'Rendering ...' while traveling and 'Current ...' otherwise" do
    live = described_class.new(current_branch: "main", current_commit: "abc").render
    expect(live).to include(">Current branch<")
    expect(live).to include(">Current commit<")

    traveling = described_class.new(
      current_branch: "main",
      current_commit: "abc",
      active_ref: "def",
      active_branch: "master"
    ).render
    expect(traveling).to include(">Rendering branch<")
    expect(traveling).to include(">Rendering commit<")
  end

  it "escapes HTML in metadata to avoid injection" do
    html = described_class.new(
      current_branch: "<script>alert(1)</script>",
      current_commit: "abc",
      active_ref: nil
    ).render

    expect(html).not_to include("<script>alert(1)</script>")
    expect(html).to include("&lt;script&gt;")
  end

  describe "diff summary" do
    def render_with(diff_info)
      described_class.new(
        current_branch: "main",
        current_commit: "abc",
        active_ref: "def",
        diff_info: diff_info
      ).render
    end

    it "is omitted entirely when no diff_info is provided" do
      html = described_class.new(current_branch: "main", current_commit: "abc").render
      expect(html).not_to include(%(<div class="rw-diff))
    end

    it "shows a neutral message when the ref has no diffs against HEAD" do
      html = render_with(changed_files: [], rendered_from_ref: [], matched: [])
      expect(html).to include("rw-diff-neutral")
      expect(html).to include("No view/asset diffs")
    end

    it "warns when there are diffs elsewhere but none on this page" do
      html = render_with(
        changed_files: ["app/views/letters/show.html.haml", "app/views/letters/_form.html.haml"],
        rendered_from_ref: ["app/views/home/index.html.haml"],
        matched: []
      )
      expect(html).to include("rw-diff-miss")
      expect(html).to include("No changed views on this page")
      expect(html).to include("app/views/letters/show.html.haml")
    end

    it "celebrates when the current page rendered at least one diffed template" do
      html = render_with(
        changed_files: ["app/views/letters/show.html.haml"],
        rendered_from_ref: ["app/views/letters/show.html.haml", "app/views/shared/_header.html.haml"],
        matched: ["app/views/letters/show.html.haml"]
      )
      expect(html).to include("rw-diff-match")
      expect(html).to include("rendered on this page")
      expect(html).to include("Matched on this page (1)")
      expect(html).to include("All changed files (1)")
    end

    it "warns when historical templates are mixed with current fallbacks" do
      html = render_with(
        changed_files: ["app/views/letters/show.html.erb"],
        rendered_from_ref: [
          "app/views/letters/show.html.erb",
          "app/views/letters/_letter.html.erb"
        ],
        rendered_from_current: ["app/views/layouts/application.html.erb"],
        preview_mode: :mixed,
        matched: ["app/views/letters/show.html.erb"]
      )

      expect(html).to include('data-preview-mode="mixed"')
      expect(html).to include("rw-provenance-mixed")
      expect(html).to include("Mixed preview: 2 historical templates, 1 current fallback")
    end
  end
end
