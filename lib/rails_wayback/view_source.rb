# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "tempfile"
require "tmpdir"

module RailsWayback
  # Materialises the view/asset directories of a given git ref into the
  # refs cache under tmp/, so a controller can prepend those directories
  # as view paths and render the historical templates.
  #
  # Only the directories listed in `configuration.view_paths` and
  # `configuration.asset_paths` are pulled from the ref. Nothing is
  # executed, and the developer's real files are never mutated.
  class ViewSource
    # Bumped whenever the materialization format changes so stale
    # cached refs from earlier gem versions get rebuilt instead of
    # being reused.
    MATERIALIZATION_VERSION = "3"

    attr_reader :configuration, :git

    def initialize(configuration: RailsWayback.configuration, git: RailsWayback::Git.new)
      @configuration = configuration
      @git = git
    end

    def materialize(ref)
      sha = git.resolve_ref(ref)
      target = configuration.refs_cache_path.join(sha)

      with_cache_lock(File::LOCK_SH) do
        next target if fresh?(target, sha)

        with_ref_lock(sha) do
          # Another process may have completed the same ref while this
          # process was waiting for the per-ref lock.
          next target if fresh?(target, sha)

          build_materialization(sha, target)
        end
      end
    end

    def view_root_for(ref)
      target = materialize(ref)
      configuration.view_paths.map { |p| target.join(p) }.select(&:directory?)
    end

    def cleanup!
      with_cache_lock(File::LOCK_EX) do
        FileUtils.rm_rf(configuration.refs_cache_path)
      end
    end

    private

    def tracked_paths
      (configuration.view_paths + configuration.asset_paths).uniq
    end

    def marker_path(target)
      target.join(".rails_wayback.sha")
    end

    def fresh?(target, sha)
      marker = marker_path(target)
      return false unless marker.file?

      contents = marker.read.strip
      expected = "#{MATERIALIZATION_VERSION}:#{sha}"
      contents == expected
    end

    def write_marker(target, sha)
      marker_path(target).write("#{MATERIALIZATION_VERSION}:#{sha}")
    end

    def build_materialization(sha, target)
      refs_root = configuration.refs_cache_path
      FileUtils.mkdir_p(refs_root)
      staging = Pathname.new(Dir.mktmpdir(".#{sha}-building-", refs_root.to_s))

      begin
        tracked_paths.each { |path| extract_path(sha, path, staging) }
        write_marker(staging, sha)

        # Keep an existing materialization available until the replacement is
        # complete. A failed extraction never removes the last known cache.
        FileUtils.rm_rf(target)
        File.rename(staging, target)
        target
      rescue MaterializationError
        raise
      rescue SystemCallError => e
        raise MaterializationError,
              "Could not materialize git ref #{sha}: #{e.message}"
      ensure
        FileUtils.rm_rf(staging) if staging.exist?
      end
    end

    # Uses `git archive | tar -x` to extract a subtree at a given ref.
    # This avoids the pitfalls of hand-rolled ls-tree + show pipelines
    # (encoding, binary files, missing directories, permissions) and
    # works with any subdirectory a git version supports.
    def extract_path(sha, path, target)
      spec = "#{sha}:#{path}"
      return unless tree_exists?(sha, path)

      dest = target.join(path)
      FileUtils.mkdir_p(dest)

      archive_cmd = ["git", "-C", git.root.to_s, "archive", "--format=tar", spec]
      tar_cmd     = ["tar", "-xf", "-", "-C", dest.to_s]

      Tempfile.create(["rails-wayback-extraction", ".log"]) do |errors|
        statuses = Open3.pipeline(archive_cmd, tar_cmd, err: errors)
        next if statuses.all?(&:success?)

        errors.flush
        errors.rewind
        details = errors.read.strip
        exits = statuses.map { |status| status.exitstatus || "unknown" }.join(", ")
        message = "Could not extract #{spec} (pipeline exit statuses: #{exits})"
        message = "#{message}: #{details}" unless details.empty?
        raise MaterializationError, message
      end
    rescue SystemCallError => e
      raise MaterializationError, "Could not extract #{spec}: #{e.message}"
    end

    def tree_exists?(sha, path)
      # `git cat-file -t <sha>:<path>` prints "tree" for directories and
      # "blob" for files. Anything else (or a non-zero exit) means the
      # path is not present at that ref, in which case we skip it.
      out, _err, status = Open3.capture3(
        "git", "-C", git.root.to_s, "cat-file", "-t", "#{sha}:#{path}"
      )
      status.success? && out.strip == "tree"
    end

    def with_cache_lock(mode, &)
      with_file_lock(configuration.cache_root_path.join(".refs.lock"), mode, &)
    end

    def with_ref_lock(sha, &)
      path = configuration.cache_root_path.join("locks", "#{sha}.lock")
      with_file_lock(path, File::LOCK_EX, &)
    end

    def with_file_lock(path, mode)
      file = acquire_file_lock(path, mode)
      yield
    ensure
      file&.close
    end

    def acquire_file_lock(path, mode)
      FileUtils.mkdir_p(path.dirname)
      file = File.open(path, File::RDWR | File::CREAT, 0o644)
      return file if file.flock(mode)

      file.close
      raise MaterializationError, "Could not lock the refs cache at #{path}"
    rescue SystemCallError => e
      file&.close
      raise MaterializationError, "Could not lock the refs cache: #{e.message}"
    end
  end
end
