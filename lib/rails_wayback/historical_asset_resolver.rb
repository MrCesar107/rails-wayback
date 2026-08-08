# frozen_string_literal: true

require "pathname"
require "rack/utils"

module RailsWayback
  class HistoricalAssetResolver
    TYPE_DIRECTORIES = {
      audio: "audios",
      font: "fonts",
      image: "images",
      javascript: "javascripts",
      stylesheet: "stylesheets",
      video: "videos"
    }.freeze
    ENCODED_TRAVERSAL = /%(?:2e|2f|5c)/i

    Resolution = Struct.new(:path, :public_path, :size_bytes, keyword_init: true)

    def resolve(root:, source:, type: nil)
      candidates(source, type).each do |candidate|
        resolution = resolve_public_path(root: root, public_path: candidate)
        return resolution if resolution
      end
      nil
    end

    def resolve_public_path(root:, public_path:)
      relative = normalize(public_path)
      return unless relative

      public_root = Pathname.new(root).join("public")
      return unless safe_public_root?(public_root)

      candidate = public_root.join(relative)
      return unless candidate.file?

      public_real = public_root.realpath
      candidate_real = candidate.realpath
      return unless under?(candidate_real, public_real)

      Resolution.new(path: candidate_real, public_path: relative, size_bytes: candidate_real.size)
    rescue SystemCallError
      nil
    end

    def self.url(sha:, public_path:, mount: RailsWayback::EngineMount.path)
      base = mount.to_s.sub(%r{/+\z}, "")
      escaped = Rack::Utils.escape_path(public_path.to_s)
      "#{base}/refs/#{sha}/assets/#{escaped}"
    end

    def self.historical_url?(source, sha:)
      source.to_s.include?("/refs/#{sha}/assets/")
    end

    private

    def candidates(source, type)
      relative = normalize(source)
      return [] unless relative

      directory = TYPE_DIRECTORIES[type&.to_sym]
      [relative, (File.join(directory, relative) if directory)].compact.uniq
    end

    def normalize(value)
      raw = value.to_s
      return unless safe_raw_path?(raw)

      segments = raw.split("/", -1)
      return if segments.any? { |segment| unsafe_segment?(segment) }

      clean = Pathname.new(raw).cleanpath.to_s
      clean unless clean == "." || clean.start_with?("../")
    rescue ArgumentError
      nil
    end

    def safe_raw_path?(raw)
      !raw.empty? && !raw.start_with?("/") &&
        !raw.include?("\0") && !raw.include?("\\") && !raw.match?(ENCODED_TRAVERSAL)
    end

    def unsafe_segment?(segment)
      segment.empty? || [".", ".."].include?(segment)
    end

    def safe_public_root?(public_root)
      stat = File.lstat(public_root)
      stat.directory? && !stat.symlink?
    rescue SystemCallError
      false
    end

    def under?(path, root)
      value = path.to_s
      base = root.to_s
      value.start_with?("#{base}#{File::SEPARATOR}")
    end
  end
end
