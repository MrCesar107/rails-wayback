# frozen_string_literal: true

require "cgi"
require "rails_wayback/bar_renderer"

module RailsWayback
  # Rack middleware that appends the wayback bar to every successful
  # HTML response of the host application while the gem is enabled.
  # Skips assets, ActionCable, non-2xx responses and non-HTML bodies so
  # it never touches anything but the developer-facing pages.
  class BarMiddleware
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
      # Always reset the per-request render tracker before invoking the
      # app so the middleware can accurately report which templates the
      # current page rendered. Cheap and thread-safe (Thread.current).
      Thread.current[RailsWayback::RENDER_TRACKER_KEY] = []

      status, headers, body = @app.call(env)
      return [status, headers, body] unless inject?(env, status, headers)

      html = read_body(body)
      snippet = build_snippet(env)
      new_html = inject(html, snippet)

      new_headers = headers.dup
      length_key = new_headers.key?("Content-Length") ? "Content-Length" : (new_headers.key?("content-length") ? "content-length" : nil)
      new_headers[length_key] = new_html.bytesize.to_s if length_key

      [status, new_headers, [new_html]]
    end

    private

    def inject?(env, status, headers)
      return false unless RailsWayback.enabled?
      return false unless status.to_i.between?(200, 299) || status.to_i.between?(400, 499)

      path = env["PATH_INFO"].to_s
      return false if SKIP_PATH_PREFIXES.any? { |prefix| path.start_with?(prefix) }

      content_type = headers["Content-Type"] || headers["content-type"] || ""
      return false unless content_type.include?("text/html")

      true
    end

    def read_body(body)
      buffer = +""
      body.each { |chunk| buffer << chunk.to_s }
      buffer
    ensure
      body.close if body.respond_to?(:close)
    end

    def inject(html, snippet)
      if html.include?("</body>")
        html.sub("</body>", "#{snippet}</body>")
      else
        html + snippet
      end
    end

    def build_snippet(env)
      git = RailsWayback::Git.new
      active_ref = extract_active_ref(env)
      active_branch = active_ref ? active_branch_for(env, git, active_ref) : nil

      renderer = BarRenderer.new(
        current_branch: safe(:current_branch, git),
        current_commit: safe(:current_commit, git),
        active_ref: active_ref,
        active_branch: active_branch,
        engine_mount: engine_mount,
        diff_info: active_ref ? build_diff_info(git, active_ref) : nil
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
    def build_diff_info(git, ref)
      config = RailsWayback.configuration
      tracked_paths = (config.view_paths + config.asset_paths).uniq
      changed_files = git.diff_paths(ref, paths: tracked_paths)

      rendered = RailsWayback::RenderProvenance.paths_by_origin(
        Thread.current[RailsWayback::RENDER_TRACKER_KEY],
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
