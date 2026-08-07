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

  it "raises an explicit error and preserves the previous cache when extraction fails" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")

      git = RailsWayback::Git.new(root: root)
      sha = git.commits("main").first.sha
      source = described_class.new(configuration: RailsWayback.configuration, git: git)
      target = RailsWayback.configuration.refs_cache_path.join(sha)
      FileUtils.mkdir_p(target)
      target.join("previous.txt").write("keep me")
      target.join(".rails_wayback.sha").write("2:#{sha}")

      archive_status = instance_double(Process::Status, success?: false, exitstatus: 128)
      tar_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:pipeline).and_return([archive_status, tar_status])

      expect { source.materialize(sha) }
        .to raise_error(RailsWayback::MaterializationError, /Could not extract/)

      expect(target.join("previous.txt").read).to eq("keep me")
      expect(target.join(".rails_wayback.sha").read).to eq("2:#{sha}")
      staging_dirs = Dir.glob(
        RailsWayback.configuration.refs_cache_path.join(".*-building-*").to_s,
        File::FNM_DOTMATCH
      )
      expect(staging_dirs).to be_empty
    end
  end

  it "serializes concurrent materializations of the same ref and rechecks freshness" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")

      started = Queue.new
      release = Queue.new
      stale_checks = Queue.new
      source_class = Class.new(described_class) do
        attr_reader :extractions

        def initialize(started:, release:, stale_checks:, **options)
          super(**options)
          @started = started
          @release = release
          @stale_checks = stale_checks
          @extractions = 0
          @counter_lock = Mutex.new
        end

        private

        def tracked_paths
          ["app/views"]
        end

        def fresh?(target, sha)
          result = super
          @stale_checks << true unless result
          result
        end

        def extract_path(sha, path, target)
          @counter_lock.synchronize { @extractions += 1 }
          @started << true
          @release.pop
          super
        end
      end

      git = RailsWayback::Git.new(root: root)
      sha = git.commits("main").first.sha
      source = source_class.new(
        configuration: RailsWayback.configuration,
        git: git,
        started: started,
        release: release,
        stale_checks: stale_checks
      )

      first = Thread.new { source.materialize(sha) }
      stale_checks.pop
      started.pop
      second = Thread.new { source.materialize(sha) }
      stale_checks.pop
      release << true

      first_result = first.value
      second_result = second.value
      expect([first_result, second_result].uniq.size).to eq(1)
      expect(source.extractions).to eq(1)
      expect(first_result.join(".rails_wayback.sha").read).to eq("3:#{sha}")
    end
  end

  it "waits for an active materialization before cleaning the refs cache" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>v1</h1>", message: "v1")

      started = Queue.new
      release = Queue.new
      cleanup_started = Queue.new
      source_class = Class.new(described_class) do
        def initialize(started:, release:, cleanup_started:, **options)
          super(**options)
          @started = started
          @release = release
          @cleanup_started = cleanup_started
        end

        private

        def tracked_paths
          ["app/views"]
        end

        def extract_path(sha, path, target)
          @started << true
          @release.pop
          super
        end

        def with_cache_lock(mode, &)
          @cleanup_started << true if mode == File::LOCK_EX
          super
        end
      end

      git = RailsWayback::Git.new(root: root)
      sha = git.commits("main").first.sha
      source = source_class.new(
        configuration: RailsWayback.configuration,
        git: git,
        started: started,
        release: release,
        cleanup_started: cleanup_started
      )

      materialization = Thread.new { source.materialize(sha) }
      started.pop
      cleanup = Thread.new { source.cleanup! }
      cleanup_started.pop
      release << true

      expect(materialization.value).to be_a(Pathname)
      cleanup.value
      expect(RailsWayback.configuration.refs_cache_path).not_to exist
    end
  end
end
