# frozen_string_literal: true

require "pathname"

module RailsWayback
  # Classifies Action View render identifiers by filesystem origin and
  # normalizes them back to paths relative to the host application. Both the
  # engine logger and toolbar use this module so they cannot drift into
  # applying different provenance rules.
  module RenderProvenance
    module_function

    def origin_for(identifier, configuration: RailsWayback.configuration)
      path = absolute_path(identifier)
      return :other unless path

      refs_root = File.expand_path(configuration.refs_cache_path.to_s)
      return :historical if under?(path, refs_root)
      return :current if current_view_roots(configuration).any? { |root| under?(path, root) }

      :other
    end

    def paths_by_origin(entries, configuration: RailsWayback.configuration)
      result = { historical: [], current: [] }

      Array(entries).each do |entry|
        identifier = identifier_from(entry)
        origin = origin_for(identifier, configuration: configuration)
        next unless result.key?(origin)

        relative = relative_path(identifier, origin, configuration)
        result[origin] << relative if relative
      end

      result.transform_values(&:uniq)
    end

    def under?(path, root)
      path == root || path.start_with?("#{root}/")
    end
    private_class_method :under?

    def absolute_path(identifier)
      value = identifier.to_s
      return nil if value.empty? || !Pathname.new(value).absolute?

      File.expand_path(value)
    end
    private_class_method :absolute_path

    def current_view_roots(configuration)
      app_root = File.expand_path(configuration.app_root_path.to_s)
      configuration.view_paths.map { |path| File.expand_path(path.to_s, app_root) }
    end
    private_class_method :current_view_roots

    def identifier_from(entry)
      case entry
      when Hash
        (entry[:identifier] || entry["identifier"]).to_s
      else
        entry.to_s
      end
    end
    private_class_method :identifier_from

    def relative_path(identifier, origin, configuration)
      path = absolute_path(identifier)
      return unless path

      case origin
      when :historical
        refs_root = File.expand_path(configuration.refs_cache_path.to_s)
        # Drop the refs root and the following SHA directory.
        path.delete_prefix("#{refs_root}/").split("/", 2)[1]
      when :current
        app_root = File.expand_path(configuration.app_root_path.to_s)
        path.delete_prefix("#{app_root}/") if under?(path, app_root)
      end
    end
    private_class_method :relative_path
  end
end
