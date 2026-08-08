# frozen_string_literal: true

RSpec.describe RailsWayback::HistoricalAssetBody do
  it "streams under a cache lease so pruning waits for the response body" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "public/archive.txt", "historical-body", message: "asset")

      exclusive_started = Queue.new
      source_class = Class.new(RailsWayback::ViewSource) do
        def initialize(exclusive_started:, **options)
          super(**options)
          @exclusive_started = exclusive_started
        end

        private

        def with_cache_lock(mode, &)
          @exclusive_started << true if mode == File::LOCK_EX
          super
        end
      end
      git = RailsWayback::Git.new(root: root)
      sha = git.current_commit
      source = source_class.new(
        configuration: RailsWayback.configuration,
        git: git,
        exclusive_started: exclusive_started
      )
      source.materialize(sha)
      RailsWayback.configuration.max_cached_refs = 0
      RailsWayback.configuration.max_cache_bytes = nil
      body = described_class.new(sha: sha, public_path: "archive.txt", view_source: source, chunk_size: 4)
      first_chunk = Queue.new
      release = Queue.new
      prune_result = Queue.new
      chunks = []

      streaming = Thread.new do
        body.each do |chunk|
          chunks << chunk
          if chunks.one?
            first_chunk << true
            release.pop
          end
        end
      end
      first_chunk.pop
      pruning = Thread.new { prune_result << source.prune! }
      exclusive_started.pop
      Thread.pass

      expect(prune_result).to be_empty
      expect(RailsWayback.configuration.refs_cache_path.join(sha)).to exist

      release << true
      streaming.value
      result = prune_result.pop
      pruning.join

      expect(chunks.join).to eq("historical-body")
      expect(result.removed.map(&:sha)).to eq([sha])
    end
  end
end
