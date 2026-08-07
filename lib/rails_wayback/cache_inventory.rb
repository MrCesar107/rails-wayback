# frozen_string_literal: true

require "find"
require "fileutils"
require "json"
require "pathname"
require "time"

module RailsWayback
  # Reads cache metadata and applies explicit LRU pruning policies.
  class CacheInventory
    MATERIALIZATION_VERSION = "4"
    METADATA_VERSION = 1
    MARKER_NAME = ".rails_wayback.sha"
    METADATA_NAME = ".rails_wayback.meta.json"
    SHA_PATTERN = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i

    Entry = Struct.new(
      :sha, :path, :size_bytes, :file_count, :last_accessed_at, :valid,
      keyword_init: true
    ) do
      def valid?
        valid
      end
    end

    Snapshot = Struct.new(:refs, keyword_init: true) do
      def ref_count
        refs.size
      end

      def size_bytes
        refs.sum(&:size_bytes)
      end

      def file_count
        refs.sum(&:file_count)
      end
    end

    PruneResult = Struct.new(:removed, :snapshot, :limits_satisfied, keyword_init: true) do
      def removed_size_bytes
        removed.sum(&:size_bytes)
      end

      def limits_satisfied?
        limits_satisfied
      end
    end

    def initialize(configuration: RailsWayback.configuration)
      @configuration = configuration
    end

    def snapshot
      Snapshot.new(refs: entry_paths.filter_map { |path| build_entry(path) })
    end

    def write_metadata(path, sha)
      size_bytes, file_count = measure(path)
      payload = {
        metadata_version: METADATA_VERSION,
        materialization_version: MATERIALIZATION_VERSION,
        sha: sha,
        size_bytes: size_bytes,
        file_count: file_count,
        created_at: Time.now.utc.iso8601
      }
      metadata_path(path).write(JSON.generate(payload))
    end

    # Caller must hold the cache's exclusive lock.
    def prune!(preserve: [])
      preserved = Array(preserve).map(&:to_s)
      entries = snapshot.refs
      removed = remove_invalid(entries, preserved)
      remaining = entries - removed

      removable = remaining.reject { |entry| preserved.include?(entry.sha) }
                           .sort_by { |entry| [entry.last_accessed_at, entry.sha] }
      while limits_exceeded?(remaining) && removable.any?
        entry = removable.shift
        remove_entry(entry)
        removed << entry
        remaining.delete(entry)
      end

      final_snapshot = Snapshot.new(refs: remaining)
      PruneResult.new(
        removed: removed,
        snapshot: final_snapshot,
        limits_satisfied: !limits_exceeded?(remaining)
      )
    end

    private

    attr_reader :configuration

    def entry_paths
      root = configuration.refs_cache_path
      return [] unless root.directory?

      root.children.sort_by { |path| path.basename.to_s }.select do |path|
        path.basename.to_s.match?(SHA_PATTERN) && File.lstat(path).directory?
      rescue SystemCallError
        false
      end
    end

    def build_entry(path)
      sha = path.basename.to_s.downcase
      marker = marker_path(path)
      valid = marker.file? && marker.read.strip == "#{MATERIALIZATION_VERSION}:#{sha}"
      size_bytes, file_count = stored_metrics(path, sha) || measure(path)
      accessed = marker.file? ? marker.mtime : path.mtime
      Entry.new(
        sha: sha,
        path: path,
        size_bytes: size_bytes,
        file_count: file_count,
        last_accessed_at: accessed,
        valid: valid
      )
    rescue SystemCallError
      nil
    end

    def stored_metrics(path, sha)
      metadata = metadata_path(path)
      return unless metadata.file?

      payload = JSON.parse(metadata.read)
      return unless payload["metadata_version"] == METADATA_VERSION
      return unless payload["materialization_version"] == MATERIALIZATION_VERSION
      return unless payload["sha"] == sha

      size_bytes = Integer(payload["size_bytes"])
      file_count = Integer(payload["file_count"])
      return if size_bytes.negative? || file_count.negative?

      [size_bytes, file_count]
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def measure(path)
      size_bytes = 0
      file_count = 0
      Find.find(path.to_s) do |entry_path|
        stat = File.lstat(entry_path)
        next if stat.directory?
        next if [marker_path(path).to_s, metadata_path(path).to_s].include?(entry_path)

        size_bytes += stat.size
        file_count += 1
      end
      [size_bytes, file_count]
    end

    def remove_invalid(entries, preserved)
      entries.reject(&:valid?).reject { |entry| preserved.include?(entry.sha) }.each do |entry|
        remove_entry(entry)
      end
    end

    def remove_entry(entry)
      FileUtils.rm_rf(entry.path)
      FileUtils.rm_f(configuration.cache_root_path.join("locks", "#{entry.sha}.lock"))
      return unless entry.path.exist?

      raise MaterializationError, "Could not remove cached ref #{entry.sha}"
    end

    def limits_exceeded?(entries)
      count_limit = normalized_limit(configuration.max_cached_refs)
      byte_limit = normalized_limit(configuration.max_cache_bytes)
      count_exceeded = count_limit && entries.size > count_limit
      bytes_exceeded = byte_limit && entries.sum(&:size_bytes) > byte_limit
      count_exceeded || bytes_exceeded
    end

    def normalized_limit(value)
      return if value.nil?

      [Integer(value), 0].max
    rescue ArgumentError, TypeError
      0
    end

    def marker_path(path)
      path.join(MARKER_NAME)
    end

    def metadata_path(path)
      path.join(METADATA_NAME)
    end
  end
end
