# frozen_string_literal: true

module RailsWayback
  class HistoricalAssetBody
    DEFAULT_CHUNK_SIZE = 64 * 1024

    def initialize(sha:, public_path:, view_source: RailsWayback::ViewSource.new,
                   resolver: RailsWayback::HistoricalAssetResolver.new,
                   chunk_size: DEFAULT_CHUNK_SIZE)
      @sha = sha
      @public_path = public_path
      @view_source = view_source
      @resolver = resolver
      @chunk_size = chunk_size
    end

    def each
      return enum_for(:each) unless block_given?

      view_source.with_materialization(sha) do |root|
        resolution = resolver.resolve_public_path(root: root, public_path: public_path)
        unless resolution
          raise RailsWayback::MaterializationError,
                "Historical public asset #{public_path.inspect} is no longer available for #{sha}"
        end

        File.open(resolution.path, "rb") do |file|
          while (chunk = file.read(chunk_size))
            yield chunk
          end
        end
      end
    end

    def close; end

    private

    attr_reader :sha, :public_path, :view_source, :resolver, :chunk_size
  end
end
