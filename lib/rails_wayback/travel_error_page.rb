# frozen_string_literal: true

require "cgi"

module RailsWayback
  # Renders a self-contained recovery response when a materialized historical
  # template cannot run against the host application's current runtime. It
  # deliberately avoids host layouts, helpers, assets, and templates because
  # any of those may be the source of the incompatibility.
  class TravelErrorPage
    MAX_ERROR_MESSAGE_BYTES = 2_000

    def initialize(branch:, error:, ref:, reset_url:)
      @branch = branch.to_s
      @error = error
      @ref = ref.to_s
      @reset_url = reset_url.to_s
    end

    def render
      <<~HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Historical preview failed</title>
          </head>
          <body>
            <h1>Historical preview failed</h1>
            <p>
              This historical template is incompatible with the current
              application code or database state.
            </p>
            #{branch_html}
            <p><strong>Commit:</strong> <code>#{escape(@ref)}</code></p>
            <p><strong>Error:</strong> <code>#{escape(error_summary)}</code></p>
            <p><a href="#{escape(@reset_url)}">Return to current version</a></p>
          </body>
        </html>
      HTML
    end

    private

    def branch_html
      return "" if @branch.empty?

      %(<p><strong>Branch:</strong> <code>#{escape(@branch)}</code></p>)
    end

    def error_summary
      message = @error.message.to_s.byteslice(0, MAX_ERROR_MESSAGE_BYTES).to_s.scrub
      "#{@error.class}: #{message}"
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
