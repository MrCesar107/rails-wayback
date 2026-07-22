# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

module RailsWayback
  # Materialises the view/asset directories of a given git ref into a
  # sandbox under tmp/, so a controller can prepend that sandbox as a
  # view path and render the historical templates.
  #
  # Only the directories listed in `configuration.view_paths` and
  # `configuration.asset_paths` are pulled from the ref. Nothing is
  # executed, and the developer's real files are never mutated.
  class ViewSource
    # Bumped whenever the materialization format changes so stale
    # sandboxes from earlier gem versions get rebuilt instead of
    # being reused.
    MATERIALIZATION_VERSION = "2"

    attr_reader :configuration, :git

    def initialize(configuration: RailsWayback.configuration, git: RailsWayback::Git.new)
      @configuration = configuration
      @git = git
    end

    def materialize(ref)
      sha = git.resolve_ref(ref)
      target = configuration.refs_cache_path.join(sha)
      return target if fresh?(target, sha)

      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      tracked_paths.each { |path| extract_path(sha, path, target) }
      write_marker(target, sha)
      target
    end

    def view_root_for(ref)
      target = materialize(ref)
      configuration.view_paths.map { |p| target.join(p) }.select(&:directory?)
    end

    def cleanup!
      FileUtils.rm_rf(configuration.refs_cache_path)
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

      Open3.pipeline(archive_cmd, tar_cmd)
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
  end
end
