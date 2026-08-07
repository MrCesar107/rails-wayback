# frozen_string_literal: true

require "cgi"
require "rails_wayback/bar_renderer"

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

    def initialize(app)
      @app = app
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
      git = RailsWayback::Git.new
      active_ref = extract_active_ref(env)
      active_branch = active_ref ? active_branch_for(env, git, active_ref) : nil

      renderer = BarRenderer.new(
        current_branch: safe(:current_branch, git),
        current_commit: safe(:current_commit, git),
        active_ref: active_ref,
        active_branch: active_branch,
        engine_mount: engine_mount,
        diff_info: active_ref ? build_diff_info(git, active_ref, tracker) : nil,
        csp_nonce: content_security_policy_nonce(env)
      )
      renderer.render
    rescue StandardError => e
      Rails.logger.warn("[rails-wayback] failed to render bar: #{e.class}: #{e.message}") if defined?(Rails)
      ""
    end

    def safe(method, git)
      git.public_send(method)
    rescue StandardError
      ""
    end

    def content_security_policy_nonce(env)
      return unless defined?(ActionDispatch::Request)

      request = ActionDispatch::Request.new(env)
      request.content_security_policy_nonce if request.respond_to?(:content_security_policy_nonce)
    rescue StandardError
      nil
    end

    # Determines the branch label to show in the bar while traveling.
    # Prefers the branch the user explicitly picked in the bar (passed
    # via the `_wayback_branch` query param, so it survives the reload).
    # Falls back to inferring it from git — useful when a developer opens
    # a shared URL that only carries `_wayback_ref`.
    def active_branch_for(env, git, ref)
      explicit = extract_active_branch(env)
      return explicit if explicit && !explicit.empty?

      git.resolve_branch_for(ref)
    rescue StandardError
      nil
    end

    # Builds the diff summary shown in the bar when a ref is active.
    # `changed_files`: view/asset paths that differ between the ref and
    # the current working tree, always scoped to the paths the gem
    # actually swaps. Rendered paths are split by origin so the toolbar can
    # warn when a successful page silently mixes historical templates with
    # current-tree fallbacks.
    def build_diff_info(git, ref, tracker)
      config = RailsWayback.configuration
      tracked_paths = (config.view_paths + config.asset_paths).uniq
      changed_files = git.diff_paths(ref, paths: tracked_paths)

      rendered = RailsWayback::RenderProvenance.paths_by_origin(
        tracker.entries,
        configuration: config
      )
      rendered_from_ref = rendered[:historical]
      rendered_from_current = rendered[:current]
      matched = changed_files & rendered_from_ref

      {
        changed_files: changed_files,
        rendered_from_ref: rendered_from_ref,
        rendered_from_current: rendered_from_current,
        preview_mode: preview_mode(rendered_from_ref, rendered_from_current),
        matched: matched
      }
    rescue StandardError => e
      Rails.logger.warn("[rails-wayback] failed to build diff info: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    def preview_mode(historical, current)
      return :mixed if historical.any? && current.any?
      return :historical if historical.any?
      return :current_fallback if current.any?

      :unknown
    end

    # Query params take priority (one-off overrides / shared links);
    # cookies keep the travel state alive as the developer navigates
    # around the app without repeating the params in every URL.
    def extract_active_ref(env)
      extract_query_param(env, "_wayback_ref") ||
        extract_cookie(env, "rails_wayback_ref")
    end

    def extract_active_branch(env)
      extract_query_param(env, "_wayback_branch") ||
        extract_cookie(env, "rails_wayback_branch")
    end

    def extract_query_param(env, name)
      query = env["QUERY_STRING"].to_s
      return nil if query.empty?

      prefix = "#{name}="
      match = query.split("&").find { |pair| pair.start_with?(prefix) }
      return nil unless match

      value = CGI.unescape(match.split("=", 2).last.to_s)
      value.empty? ? nil : value
    end

    def extract_cookie(env, name)
      header = env["HTTP_COOKIE"].to_s
      return nil if header.empty?

      prefix = "#{name}="
      match = header.split(/;\s*/).find { |pair| pair.start_with?(prefix) }
      return nil unless match

      value = CGI.unescape(match.split("=", 2).last.to_s)
      value.empty? ? nil : value
    end

    def engine_mount
      RailsWayback::Engine.routes.default_url_options[:script_name] ||
        RailsWayback::Engine.routes.find_script_name({}) ||
        "/rails-wayback"
    rescue StandardError
      "/rails-wayback"
    end
  end
end
