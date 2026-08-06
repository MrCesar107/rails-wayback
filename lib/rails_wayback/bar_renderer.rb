# frozen_string_literal: true

require "json"
require "cgi"
require "erb"

module RailsWayback
  # Builds the HTML/CSS/JS payload that the middleware injects into
  # every HTML response so the developer can travel from any page of
  # their app without visiting a dedicated route.
  class BarRenderer
    TEMPLATE = ERB.new(File.read(File.expand_path("bar_renderer.html.erb", __dir__))).freeze
    STYLES = File.read(File.expand_path("bar_renderer.css", __dir__)).freeze
    SCRIPT = File.read(File.expand_path("bar_renderer.js", __dir__)).freeze

    def initialize(current_branch:, current_commit:, active_ref: nil, active_branch: nil,
                   engine_mount: "/rails-wayback", diff_info: nil)
      @current_branch = current_branch
      @current_commit = current_commit
      @active_ref = active_ref
      @active_branch = active_branch
      @engine_mount = engine_mount
      @diff_info = diff_info
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
          <span class="rw-diff-msg">#{escape(message)}</span>
          #{list_html}
        </div>
      HTML
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

    def styles
      STYLES
    end

    def script
      SCRIPT
    end
  end
end
