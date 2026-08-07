# frozen_string_literal: true

module RailsWayback
  # Authorizes immutable commits before historical files enter Action View.
  class RefPolicy
    ENV_KEY = "rails_wayback.ref_policy"
    FULL_SHA = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i

    Result = Struct.new(:input, :sha, :trusted_refs, :reason, :message, keyword_init: true) do
      def accepted?
        reason.nil?
      end

      def rejected?
        !accepted?
      end
    end

    def initialize(configuration: RailsWayback.configuration, git: RailsWayback::Git.new)
      @configuration = configuration
      @git = git
    end

    def authorize(ref)
      input = ref.to_s

      unless valid_sha?(input)
        return rejection(input, :invalid_format, "expected a full 40- or 64-character commit SHA")
      end

      sha = git.resolve_ref(input).downcase
      trusted = trusted_refs_containing(sha)
      if trusted.empty?
        return rejection(input, :untrusted_ref, "commit is not reachable from a trusted Git ref", sha: sha)
      end

      Result.new(input: input, sha: sha, trusted_refs: trusted.freeze)
    rescue RefNotFoundError
      rejection(input, :unknown_ref, "commit does not exist in the local repository")
    end

    private

    attr_reader :configuration, :git

    def valid_sha?(ref)
      ref.match?(FULL_SHA)
    end

    def trusted_refs_containing(sha)
      patterns = Array(configuration.trusted_ref_patterns).map(&:to_s)
      git.refs_containing(sha).select do |ref|
        patterns.any? { |pattern| File.fnmatch?(pattern, ref) }
      end.sort
    end

    def rejection(input, reason, detail, sha: nil)
      label = (sha || input).inspect
      label = "#{label.byteslice(0, 120)}..." if label.bytesize > 120
      message = "Rejected travel ref #{label}: #{detail}."
      Result.new(input: input, sha: sha, trusted_refs: [].freeze, reason: reason, message: message)
    end
  end
end
