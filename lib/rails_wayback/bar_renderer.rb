# frozen_string_literal: true

require "cgi"
require "erb"
require "rails_wayback/version"

module RailsWayback
  # Builds the HTML payload that the middleware injects into every HTML
  # response and references the toolbar's same-origin CSS and JavaScript.
  class BarRenderer
    TEMPLATE = ERB.new(File.read(File.expand_path("bar_renderer.html.erb", __dir__))).freeze
    STYLES = File.read(File.expand_path("bar_renderer.css", __dir__)).freeze
    SCRIPT = File.read(File.expand_path("bar_renderer.js", __dir__)).freeze

    def initialize(current_branch:, current_commit:, active_ref: nil, active_branch: nil,
                   engine_mount: "/rails-wayback", diff_info: nil, csp_nonce: nil, ref_error: nil)
      @current_branch = current_branch
      @current_commit = current_commit
      @active_ref = active_ref
      @active_branch = active_branch
      @engine_mount = normalize_mount(engine_mount)
      @diff_info = diff_info
      @csp_nonce = csp_nonce.to_s
      @ref_error = ref_error.to_s
    end

    def render
      TEMPLATE.result(binding)
    end

    private

    def branch_label
      @active_ref ? "Rendering branch" : "Current branch"
    end

    def commit_label
      @active_ref ? "Rendering commit" : "Current commit"
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end

    # Second row of the bar shown only while traveling. Tells the
    # developer whether the current page actually contains any changed
    # templates for the active ref, so they don't waste time refreshing
    # a page that has no diffs vs the ref they picked.
    def diff_summary_html
      return "" unless @diff_info

      changed  = Array(@diff_info[:changed_files])
      matched  = Array(@diff_info[:matched])
      total    = changed.size

      if total.zero?
        message = %(No view/asset diffs between HEAD and this ref.)
        css_class = "rw-diff rw-diff-neutral"
        list_html = ""
      elsif matched.any?
        message = %(#{matched.size} changed view#{"s" if matched.size != 1} rendered on this page.)
        css_class = "rw-diff rw-diff-match"
        list_html = diff_details("Matched on this page (#{matched.size})", matched) +
                    diff_details("All changed files (#{total})", changed)
      else
        message = %(No changed views on this page. #{total} file#{"s" if total != 1} differ elsewhere.)
        css_class = "rw-diff rw-diff-miss"
        list_html = diff_details("Changed files (#{total})", changed)
      end

      <<~HTML.strip
        <div class="#{css_class}">
          #{provenance_html}
          <span class="rw-diff-msg">#{escape(message)}</span>
          #{list_html}
        </div>
      HTML
    end

    def provenance_html
      historical = Array(@diff_info[:rendered_from_ref])
      current = Array(@diff_info[:rendered_from_current])

      message, css_class = case @diff_info[:preview_mode]&.to_sym
                           when :mixed
                             ["Mixed preview: #{count_label(historical.size, "historical template")}, " \
                              "#{count_label(current.size, "current fallback")}.", "rw-provenance-mixed"]
                           when :historical
                             ["Historical preview: #{count_label(historical.size, "historical template")}.",
                              "rw-provenance-historical"]
                           when :current_fallback
                             ["Current fallback: no historical templates rendered " \
                              "(#{count_label(current.size, "current template")}).", "rw-provenance-current"]
                           else
                             return ""
                           end

      %(<span class="rw-provenance #{css_class}">#{escape(message)}</span>)
    end

    def count_label(count, singular)
      "#{count} #{singular}#{"s" unless count == 1}"
    end

    def diff_details(summary, files)
      items = files.map { |f| %(<li>#{escape(f)}</li>) }.join
      <<~HTML.strip
        <details class="rw-diff-details">
          <summary>#{escape(summary)}</summary>
          <ul>#{items}</ul>
        </details>
      HTML
    end

    def stylesheet_url
      asset_url("bar.css")
    end

    def javascript_url
      asset_url("bar.js")
    end

    def asset_url(filename)
      "#{@engine_mount}/assets/#{filename}?v=#{RailsWayback::VERSION}"
    end

    def nonce_attribute
      return "" if @csp_nonce.empty?

      %( nonce="#{escape(@csp_nonce)}")
    end

    def normalize_mount(value)
      mount = value.to_s
      mount = "/rails-wayback" if mount.empty?
      mount.sub(%r{/+\z}, "")
    end
  end
end
