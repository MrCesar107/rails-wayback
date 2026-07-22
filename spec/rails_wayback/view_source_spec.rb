# frozen_string_literal: true

RSpec.describe RailsWayback::ViewSource do
  it "materialises the configured view paths for a given ref" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v2</h1>", message: "v2")

      git = RailsWayback::Git.new(root: root)
      first_sha = git.commits("main").last.sha

      source = described_class.new(configuration: RailsWayback.configuration, git: git)
      sandbox = source.materialize(first_sha)

      expect(sandbox).to be_a(Pathname)
      view_file = sandbox.join("app/views/home/index.html.erb")
      expect(view_file).to exist
      expect(view_file.read).to include("v1")
    end
  end

  it "caches subsequent materializations of the same ref" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")

      git = RailsWayback::Git.new(root: root)
      sha = git.commits("main").first.sha
      source = described_class.new(configuration: RailsWayback.configuration, git: git)

      first_call = source.materialize(sha)
      expect(source).not_to receive(:extract_path)
      second_call = source.materialize(sha)

      expect(second_call).to eq(first_call)
    end
  end
end
