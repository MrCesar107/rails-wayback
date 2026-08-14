# frozen_string_literal: true

require "cgi"
require "action_view"
require "rails_wayback/git_reference"
require "rails_wayback/version"

module RailsWayback
  # Builds the HTML payload that the middleware injects into every HTML
  # response and references the toolbar's same-origin CSS and JavaScript.
  class BarRenderer
    VIEW_ROOT = File.expand_path("../../app/views", __dir__)
    VIEW_PATH = File.join(VIEW_ROOT, "rails_wayback/toolbar/_toolbar.html.erb")
    VIEW_CLASS = ActionView::Base.with_empty_template_cache
    STYLES = File.read(File.expand_path("bar_renderer.css", __dir__)).freeze
    SEARCH_SCRIPT = File.read(File.expand_path("bar_search.js", __dir__)).freeze
    COMBOBOX_SCRIPT = File.read(File.expand_path("bar_combobox.js", __dir__)).freeze
    TOOLBAR_SCRIPT = File.read(File.expand_path("bar_renderer.js", __dir__)).freeze
    SCRIPT = [SEARCH_SCRIPT, COMBOBOX_SCRIPT, TOOLBAR_SCRIPT].join("\n").freeze

    def initialize(current_branch:, current_commit:, active_ref: nil, active_branch: nil,
                   authenticity_token: nil, commits: [], engine_mount: "/rails-wayback",
                   diff_info: nil, csp_nonce: nil, ref_error: nil, references: [], return_to: "/",
                   selected_branch: nil, selected_commit: nil)
      @current_branch = current_branch
      @current_commit = current_commit
      @active_ref = active_ref
      @active_branch = active_branch
      @authenticity_token = authenticity_token.to_s
      @commits = commits
      @engine_mount = normalize_mount(engine_mount)
      @diff_info = diff_info
      @csp_nonce = csp_nonce.to_s
      @ref_error = ref_error.to_s
      @references = references
      @return_to = return_to.to_s
      @selected_branch = selected_branch || matching_reference&.full_name.to_s
      @selected_commit = selected_commit || matching_commit&.sha.to_s
    end

    def render
      view = VIEW_CLASS.with_view_paths([VIEW_ROOT], view_assigns)
      view.render(
        partial: "rails_wayback/toolbar/toolbar",
        locals: {
          branch_label: branch_label,
          commit_label: commit_label,
          commit_label_for: method(:commit_label_for),
          diff_summary_html: diff_summary_html,
          javascript_url: javascript_url,
          stylesheet_url: stylesheet_url
        }
      )
    end

    private

    def matching_reference
      selection = @active_branch || @current_branch
      GitReference.find(@references, selection) || @references.first
    end

    def matching_commit
      selection = @active_ref || @current_commit
      @commits.find { |commit| commit.sha == selection } || @commits.first
    end

    def commit_label_for(commit)
      "#{commit.short_sha} — #{commit.subject.to_s.slice(0, 80)}"
    end

    def view_assigns
      instance_variables.to_h do |name|
        [name.to_s.delete_prefix("@"), instance_variable_get(name)]
      end
    end

    def branch_label
      @active_ref ? "Rendering ref" : "Current ref"
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
          #{asset_provenance_html}
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

    def asset_provenance_html
      historical = Array(@diff_info[:historical_assets])
      current = Array(@diff_info[:current_asset_fallbacks])
      return "" if historical.empty? && current.empty?

      labels = []
      labels << count_label(historical.size, "historical asset") if historical.any?
      labels << count_label(current.size, "current asset fallback") if current.any?
      css_class = current.any? ? "rw-provenance-mixed" : "rw-provenance-historical"
      %(<span class="rw-provenance #{css_class}">Assets: #{escape(labels.join(", "))}.</span>)
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

    def normalize_mount(value)
      mount = value.to_s
      mount = "/rails-wayback" if mount.empty?
      mount.sub(%r{/+\z}, "")
    end
  end
end
