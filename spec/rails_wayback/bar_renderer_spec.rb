# frozen_string_literal: true

require "rails_wayback/bar_renderer"

RSpec.describe RailsWayback::BarRenderer do
  it "renders the isolated engine view instead of a template under lib" do
    expect(described_class::VIEW_PATH)
      .to end_with("app/views/rails_wayback/toolbar/_toolbar.html.erb")
    expect(File).to exist(described_class::VIEW_PATH)
    expect(File).not_to exist(File.expand_path("../../lib/rails_wayback/bar_renderer.html.erb", __dir__))
  end

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
    expect(html).to include("Historical templates execute Ruby in this process")
    expect(html).not_to include("<style")
    expect(html).not_to include("(function ()")
  end

  it "renders accessible searchable dropdowns for refs and commits" do
    html = described_class.new(current_branch: "main", current_commit: "abc1234").render

    expect(html).to include(
      "data-rw-branch-combobox",
      "data-rw-branch-trigger",
      'aria-haspopup="listbox"',
      'aria-expanded="false"',
      'type="search" data-rw-branch-search',
      'aria-label="Search Git refs"',
      'aria-controls="rails-wayback-branches"',
      'id="rails-wayback-branches" data-rw-branch-options role="listbox"',
      'data-rw-branch-results role="status" aria-live="polite"',
      "data-rw-commit-combobox",
      "data-rw-commit-trigger",
      'type="search" data-rw-commit-search',
      'aria-label="Search commits"',
      'aria-controls="rails-wayback-commits"',
      'id="rails-wayback-commits" data-rw-commit-options role="listbox"',
      'data-rw-commit-results role="status" aria-live="polite"'
    )
    expect(html).to match(/data-rw-branch-dropdown[^>]*hidden.*data-rw-branch-search/m)
    expect(html).to match(/data-rw-commit-dropdown[^>]*hidden.*data-rw-commit-search/m)
    expect(html).to include("<select")
  end

  it "renders an HTML-first travel form before JavaScript enhancement" do
    reference = RailsWayback::Git::Reference.new(
      full_name: "refs/heads/main",
      name: "main",
      kind: :branch,
      label: "main"
    )
    commit = RailsWayback::Git::Commit.new(
      sha: "a" * 40,
      short_sha: "aaaaaaa",
      subject: "Current work"
    )

    html = described_class.new(
      authenticity_token: "csrf-token",
      commits: [commit],
      current_branch: "main",
      current_commit: commit.sha,
      references: [reference],
      return_to: "/letters?tab=preview"
    ).render

    expect(html).to include(
      'action="/rails-wayback/travel" method="post"',
      'name="authenticity_token" value="csrf-token"',
      'name="return_to" value="/letters?tab=preview"',
      'name="confirmed" value="true"',
      "data-rw-trust-confirmation",
      "required",
      'name="branch" data-rw-branch-native',
      '<option selected="selected" value="refs/heads/main">main</option>',
      'name="ref" data-rw-commit-native',
      %(<option selected="selected" value="#{commit.sha}">aaaaaaa — Current work</option>),
      "data-rw-enhanced hidden",
      'action="/rails-wayback/travel" method="post" data-rw-reset-form',
      'name="_method" value="delete"'
    )
  end

  it "uses async functions for toolbar requests without promise callback chains" do
    script = described_class::SCRIPT

    expect(script).to include(
      "class RailsWaybackToolbar",
      "class RailsWaybackCombobox",
      "async fetchBranches()",
      "async fetchCommits(branch, selectedCommit)"
    )
    expect(script).not_to include(".then(")
  end

  it "defines an explicit dependency-free toolbar lifecycle" do
    script = described_class::SCRIPT

    expect(script).to include(
      "connect()",
      "disconnect()",
      "new this.AbortController()"
    )
  end

  it "renders rejected refs as escaped toolbar warnings" do
    html = described_class.new(
      current_branch: "main",
      current_commit: "abc1234",
      ref_error: %(<script>alert("no")</script>)
    ).render

    expect(html).to include("rw-ref-rejected")
    expect(html).to include("data-ref-error=")
    expect(html).to include("&lt;script&gt;alert(&quot;no&quot;)&lt;/script&gt;")
    expect(html).not_to include(%(<script>alert("no")</script>))
  end

  it "requires first-travel confirmation in the browser session" do
    expect(described_class::SCRIPT).to include(
      "window.confirm(",
      "window.sessionStorage.getItem(key)",
      'stateEl.textContent = "Travel rejected"',
      "Continue only if you trust this commit"
    )
  end

  it "leaves travel cookies and redirects to the Rails controller" do
    expect(described_class::SCRIPT).to include(
      'addEventListener("submit"',
      "trustWarningAccepted()"
    )
    expect(described_class::SCRIPT).not_to include(
      "document.cookie",
      "location.assign",
      'searchParams.set("_wayback_ref"',
      '"/reset"'
    )
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
    expect(live).to include(">Current ref<")
    expect(live).to include(">Current commit<")

    traveling = described_class.new(
      current_branch: "main",
      current_commit: "abc",
      active_ref: "def",
      active_branch: "master"
    ).render
    expect(traveling).to include(">Rendering ref<")
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

    it "reports historical assets and current asset fallbacks" do
      html = render_with(
        changed_files: [],
        rendered_from_ref: [],
        historical_assets: ["public/theme.css", "public/logo.svg"],
        current_asset_fallbacks: ["missing.css"],
        matched: []
      )

      expect(html).to include("rw-provenance-mixed")
      expect(html).to include("Assets: 2 historical assets, 1 current asset fallback.")
    end
  end
end
