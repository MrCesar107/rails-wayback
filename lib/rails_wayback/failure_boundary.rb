# frozen_string_literal: true

module RailsWayback
  # Internal result boundary for optional work that must not break host pages.
  class FailureBoundary
    Failure = Data.define(:context, :exception_class, :message) do
      def summary
        "#{exception_class}: #{message}"
      end
    end

    Result = Data.define(:value, :failure) do
      def success?
        failure.nil?
      end

      def failure?
        !success?
      end
    end

    def initialize(logger: default_logger)
      @logger = logger
    end

    def capture(context, fallback:, rescue_errors: [StandardError])
      Result.new(value: yield, failure: nil)
    rescue StandardError => e
      raise unless Array(rescue_errors).any? { |error_class| e.is_a?(error_class) }

      failure = Failure.new(context: context, exception_class: e.class.name, message: e.message)
      logger&.warn("[rails-wayback] #{context} failed: #{failure.summary}")
      Result.new(value: fallback, failure: failure)
    end

    private

    attr_reader :logger

    def default_logger
      Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
    end
  end
end
