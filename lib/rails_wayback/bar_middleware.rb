# frozen_string_literal: true

require "rails_wayback/bar_renderer"
require "rails_wayback/failure_boundary"
require "rails_wayback/toolbar_state"

module RailsWayback
  # Rack middleware that appends the wayback bar to every successful
  # or client-error HTML response of the host application while the gem
  # is enabled. Only complete, bounded Rack-buffered documents are
  # transformed; streaming and otherwise unsafe responses pass through.
  class BarMiddleware
    UNSAFE_STATUSES = [204, 205, 206].freeze
    UNSAFE_RESPONSE_HEADERS = %w[
      transfer-encoding
      content-range
      rack.hijack
      x-sendfile
      x-accel-redirect
    ].freeze
    INVALIDATED_RESPONSE_HEADERS = %w[
      etag
      content-md5
      digest
      content-digest
      repr-digest
      content-range
      accept-ranges
    ].freeze
    SKIP_PATH_PREFIXES = %w[
      /assets
      /packs
      /rails/
      /cable
      /rails-wayback
    ].freeze

    def initialize(app, failure_boundary: RailsWayback::FailureBoundary.new)
      @app = app
      @failure_boundary = failure_boundary
    end

    def call(env)
      tracker = RailsWayback::RenderTracker.new
      RailsWayback::RenderContext.with(tracker) { call_with_tracker(env, tracker) }
    ensure
      tracker&.close
    end

    private

    def call_with_tracker(env, tracker)
      response = @app.call(env)
      status, headers, body = response
      return response unless inject?(env, status, headers, body)

      parts = body.to_ary
      return [status, headers, parts] unless body_within_limit?(parts)

      html = parts.join
      return [status, headers, parts] unless injectable_document?(html)

      snippet = build_snippet(env, tracker)
      return [status, headers, parts] if snippet.empty?

      new_html = inject(html, snippet)
      [status, repaired_headers(headers, new_html), [new_html]]
    end

    def inject?(env, status, headers, body)
      RailsWayback.enabled? &&
        request_injectable?(env) &&
        response_injectable?(status, headers) &&
        body_injectable?(body, headers)
    end

    def request_injectable?(env)
      return false if env["REQUEST_METHOD"].to_s.casecmp?("HEAD")

      path = env["PATH_INFO"].to_s
      SKIP_PATH_PREFIXES.none? { |prefix| path.start_with?(prefix) }
    end

    def response_injectable?(status, headers)
      injectable_status?(status) &&
        html_response?(headers) &&
        identity_encoded?(headers) &&
        !attachment?(headers) &&
        !no_transform?(headers)
    end

    def injectable_status?(status)
      code = status.to_i
      (code.between?(200, 299) || code.between?(400, 499)) && !UNSAFE_STATUSES.include?(code)
    end

    def body_injectable?(body, headers)
      UNSAFE_RESPONSE_HEADERS.none? { |name| header_present?(headers, name) } &&
        !body.respond_to?(:to_path) &&
        body.respond_to?(:to_ary) &&
        declared_body_within_limit?(headers)
    end

    def html_response?(headers)
      media_type = header_value(headers, "content-type").to_s.split(";", 2).first
      media_type.strip.casecmp?("text/html")
    end

    def identity_encoded?(headers)
      value = header_value(headers, "content-encoding").to_s.strip
      return true if value.empty?

      value.split(",").all? { |encoding| encoding.strip.casecmp?("identity") }
    end

    def attachment?(headers)
      header_value(headers, "content-disposition").to_s.match?(/\battachment\b/i)
    end

    def no_transform?(headers)
      header_value(headers, "cache-control").to_s.match?(/\bno-transform\b/i)
    end

    def declared_body_within_limit?(headers)
      length = integer_header(headers, "content-length")
      return false if length&.zero?

      limit = max_response_bytes
      limit.nil? || length.nil? || length <= limit
    end

    def body_within_limit?(parts)
      limit = max_response_bytes
      limit.nil? || parts.sum(&:bytesize) <= limit
    end

    def max_response_bytes
      value = RailsWayback.configuration.max_response_bytes
      value.nil? ? nil : Integer(value)
    end

    def integer_header(headers, name)
      value = header_value(headers, name)
      value.nil? ? nil : Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end

    def injectable_document?(html)
      html.match?(/<body(?:\s|>)/i) &&
        html.match?(%r{</body\s*>}i) &&
        !html.match?(/\bid=(["'])rails-wayback-bar\1/i)
    end

    def inject(html, snippet)
      html.sub(%r{</body\s*>}i) { |closing_tag| "#{snippet}#{closing_tag}" }
    end

    def repaired_headers(headers, html)
      repaired = headers.dup
      INVALIDATED_RESPONSE_HEADERS.each { |name| delete_header(repaired, name) }
      set_header(repaired, "content-length", html.bytesize.to_s)
      add_no_store(repaired)
      repaired
    end

    def add_no_store(headers)
      current = header_value(headers, "cache-control").to_s
      return if current.match?(/(?:\A|,)\s*no-store\s*(?:,|\z)/i)

      set_header(headers, "cache-control", current.empty? ? "no-store" : "#{current}, no-store")
    end

    def header_present?(headers, name)
      !header_key(headers, name).nil?
    end

    def header_value(headers, name)
      key = header_key(headers, name)
      key ? headers[key] : nil
    end

    def header_key(headers, name)
      headers.keys.find { |key| key.to_s.casecmp?(name) }
    end

    def set_header(headers, name, value)
      headers[header_key(headers, name) || name] = value
    end

    def delete_header(headers, name)
      key = header_key(headers, name)
      headers.delete(key) if key
    end

    def build_snippet(env, tracker)
      @failure_boundary.capture("render toolbar", fallback: "") do
        attributes = RailsWayback::ToolbarState.new(env: env, tracker: tracker).to_h
        BarRenderer.new(**attributes).render
      end.value
    end
  end
end
