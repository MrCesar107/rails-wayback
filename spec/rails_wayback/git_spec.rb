# frozen_string_literal: true

RSpec.describe RailsWayback::Git do
  it "lists branches, commits and resolves refs against the host repo" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v2</h1>", message: "v2")

      git = described_class.new(root: root)

      expect(git.repository?).to be(true)
      expect(git.branches).to include("main")
      expect(git.current_branch).to eq("main")

      commits = git.commits("main")
      expect(commits.size).to eq(2)
      expect(commits.first.subject).to eq("v2")

      first_sha = commits.last.sha
      expect(git.resolve_ref(first_sha)).to eq(first_sha)
      expect(git.show(first_sha, "app/views/home/index.html.erb")).to include("v1")
    end
  end

  it "raises RefNotFoundError for unknown refs" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "README.md", "hi", message: "init")

      git = described_class.new(root: root)
      expect { git.resolve_ref("does-not-exist") }.to raise_error(RailsWayback::RefNotFoundError)
    end
  end

  it "reports a missing Git executable with an actionable error" do
    git = described_class.new(root: "/tmp")
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git")

    expect { git.current_branch }
      .to raise_error(described_class::ExecutableNotFoundError, /`git`.*rails-wayback doctor/)
  end

  describe "#diff_paths" do
    it "returns only files under the requested pathspecs that differ between ref and working tree" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")
        SpecSupport.commit_file(root, "app/views/home/show.html.erb",  "<h1>show v1</h1>", message: "show v1")
        SpecSupport.commit_file(root, "config/routes.rb", "Rails.app", message: "routes")

        git = described_class.new(root: root)
        base = git.current_commit

        SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v2</h1>", message: "v2")
        SpecSupport.commit_file(root, "config/routes.rb", "Rails.app # tweaked", message: "routes 2")

        changed = git.diff_paths(base, paths: ["app/views"])

        expect(changed).to include("app/views/home/index.html.erb")
        expect(changed).not_to include("app/views/home/show.html.erb")
        expect(changed).not_to include("config/routes.rb")
      end
    end

    it "returns [] and does not raise when the ref is unknown" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")

        git = described_class.new(root: root)
        expect(git.diff_paths("does-not-exist", paths: ["app/views"])).to eq([])
      end
    end
  end

  describe "#resolve_branch_for" do
    it "returns the local branch that contains the sha, preferring one different from HEAD" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")

        Dir.chdir(root) { SpecSupport.run("git", "checkout", "--quiet", "-b", "feature") }
        SpecSupport.commit_file(root, "feature.txt", "wip", message: "feature commit")
        feature_sha = described_class.new(root: root).current_commit
        Dir.chdir(root) { SpecSupport.run("git", "checkout", "--quiet", "main") }

        git = described_class.new(root: root)
        expect(git.current_branch).to eq("main")

        # A sha only in `feature`: resolve to `feature`.
        expect(git.resolve_branch_for(feature_sha)).to eq("feature")

        # A sha in main only: falls back to `main` (the only container).
        main_sha = git.current_commit
        expect(git.resolve_branch_for(main_sha)).to eq("main")
      end
    end

    it "returns nil for unknown shas without raising" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")

        git = described_class.new(root: root)
        expect(git.resolve_branch_for("deadbeef")).to be_nil
      end
    end
  end

  it "lists the full refs that contain a commit" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "README.md", "hi", message: "init")
      sha = described_class.new(root: root).current_commit
      SpecSupport.run("git", "-C", root.to_s, "branch", "feature/nested", sha)
      SpecSupport.run("git", "-C", root.to_s, "tag", "preview", sha)

      refs = described_class.new(root: root).refs_containing(sha)

      expect(refs).to include("refs/heads/main", "refs/heads/feature/nested", "refs/tags/preview")
    end
  end
end
