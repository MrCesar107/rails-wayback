# frozen_string_literal: true

module RailsWayback
  module AssetProvenance
    EVENT_PREFIX = "rails_wayback.asset."
    ORIGINS = %i[historical current].freeze

    module_function

    def record(origin:, identifier:)
      return unless ORIGINS.include?(origin.to_sym)

      RailsWayback::RenderContext.current&.record(
        event: "#{EVENT_PREFIX}#{origin}",
        identifier: identifier
      )
    end

    def paths_by_origin(entries)
      result = { historical: [], current: [] }
      Array(entries).each do |entry|
        event = entry_value(entry, :event)
        next unless event.start_with?(EVENT_PREFIX)

        origin = event.delete_prefix(EVENT_PREFIX).to_sym
        next unless result.key?(origin)

        identifier = entry_value(entry, :identifier)
        result[origin] << identifier unless identifier.empty?
      end
      result.transform_values(&:uniq)
    end

    def entry_value(entry, key)
      return "" unless entry.is_a?(Hash)

      (entry[key] || entry[key.to_s]).to_s
    end
    private_class_method :entry_value
  end
end
