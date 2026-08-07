# frozen_string_literal: true

RSpec.describe RailsWayback::CacheInventory do
  def create_cache_entry(root, sha, contents:, accessed_at:, valid: true)
    path = root.join("tmp/rails_wayback/refs", sha)
    file = path.join("app/views/example.html.erb")
    FileUtils.mkdir_p(file.dirname)
    file.write(contents)
    marker = path.join(described_class::MARKER_NAME)
    version = valid ? described_class::MATERIALIZATION_VERSION : "old"
    marker.write("#{version}:#{sha}")
    described_class.new.write_metadata(path, sha)
    File.utime(accessed_at, accessed_at, marker)
    lock = root.join("tmp/rails_wayback/locks", "#{sha}.lock")
    FileUtils.mkdir_p(lock.dirname)
    lock.write("")
    path
  end

  it "reports deterministic metadata-backed cache usage" do
    SpecSupport.with_tmp_root do |root|
      sha = "a" * 40
      path = create_cache_entry(root, sha, contents: "hello", accessed_at: Time.at(10).utc)

      snapshot = described_class.new.snapshot
      entry = snapshot.refs.fetch(0)

      expect(snapshot.ref_count).to eq(1)
      expect(snapshot.size_bytes).to eq(5)
      expect(snapshot.file_count).to eq(1)
      expect(entry).to have_attributes(sha: sha, path: path, last_accessed_at: Time.at(10).utc)
      expect(entry).to be_valid
    end
  end

  it "falls back to measuring entries when stored metadata is corrupt" do
    SpecSupport.with_tmp_root do |root|
      sha = "b" * 40
      path = create_cache_entry(root, sha, contents: "fallback", accessed_at: Time.at(20).utc)
      path.join(described_class::METADATA_NAME).write("not-json")

      entry = described_class.new.snapshot.refs.fetch(0)

      expect(entry.size_bytes).to eq(8)
      expect(entry.file_count).to eq(1)
      expect(entry).to be_valid
    end
  end

  it "prunes invalid and least-recently-used refs and their lock files" do
    SpecSupport.with_tmp_root do |root|
      configuration = RailsWayback.configuration
      configuration.max_cached_refs = 2
      configuration.max_cache_bytes = nil
      oldest = "a" * 40
      middle = "b" * 40
      newest = "c" * 40
      invalid = "d" * 40
      create_cache_entry(root, oldest, contents: "old", accessed_at: Time.at(10).utc)
      create_cache_entry(root, middle, contents: "middle", accessed_at: Time.at(20).utc)
      create_cache_entry(root, newest, contents: "new", accessed_at: Time.at(30).utc)
      create_cache_entry(root, invalid, contents: "invalid", accessed_at: Time.at(40).utc, valid: false)

      result = RailsWayback::ViewSource.new.prune!

      expect(result).to be_limits_satisfied
      expect(result.removed.map(&:sha)).to contain_exactly(invalid, oldest)
      expect(result.snapshot.refs.map(&:sha)).to eq([middle, newest])
      expect(configuration.refs_cache_path.join(oldest)).not_to exist
      expect(configuration.cache_root_path.join("locks", "#{oldest}.lock")).not_to exist
    end
  end

  it "applies the byte limit and reports when a preserved ref alone exceeds it" do
    SpecSupport.with_tmp_root do |root|
      configuration = RailsWayback.configuration
      configuration.max_cached_refs = nil
      configuration.max_cache_bytes = 10
      small = "a" * 40
      large = "b" * 40
      create_cache_entry(root, small, contents: "12345", accessed_at: Time.at(10).utc)
      create_cache_entry(root, large, contents: "x" * 20, accessed_at: Time.at(20).utc)

      result = RailsWayback::ViewSource.new.prune!(preserve: [large])

      expect(result.removed.map(&:sha)).to eq([small])
      expect(result.snapshot.refs.map(&:sha)).to eq([large])
      expect(result).not_to be_limits_satisfied
    end
  end
end
