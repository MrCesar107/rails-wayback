# frozen_string_literal: true

module RailsWayback
  # Internal value object for canonical Git reference presentation and lookup.
  GitReference = Data.define(:full_name, :name, :kind, :label)
  GitReference::PREFIXES = {
    "refs/heads/" => :branch,
    "refs/remotes/" => :remote,
    "refs/tags/" => :tag
  }.freeze
  GitReference::KIND_ORDER = { branch: 0, remote: 1, tag: 2 }.freeze

  class GitReference
    class << self
      def parse(full_name)
        value = full_name.to_s
        prefix, kind = PREFIXES.find { |candidate, _value| value.start_with?(candidate) }
        return unless prefix

        name = value.delete_prefix(prefix)
        new(full_name: value, name: name, kind: kind, label: kind == :tag ? "tag:#{name}" : name)
      end

      def find(references, selector)
        input = selector.to_s
        available = Array(references)
        available.find { |reference| full_name_for(reference) == input } ||
          available.find { |reference| matches_alias?(reference, input) }
      end

      def name_for(reference)
        parsed(reference)&.name
      end

      def label_for(reference)
        parsed(reference)&.label
      end

      private

      def full_name_for(reference)
        reference.respond_to?(:full_name) ? reference.full_name.to_s : reference.to_s
      end

      def matches_alias?(reference, selector)
        candidate = parsed(reference)
        candidate && (candidate.name == selector || candidate.label == selector)
      end

      def parsed(reference)
        return reference if reference.is_a?(self)

        parse(full_name_for(reference))
      end
    end
  end
end
