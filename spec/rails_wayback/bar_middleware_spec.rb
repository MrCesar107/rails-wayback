# frozen_string_literal: true

require "rails_wayback/bar_middleware"
require "rack/lint"
require "rack/mock"

RSpec.describe RailsWayback::BarMiddleware do
  let(:downstream_body) { "<html><body><h1>hi</h1></body></html>" }
  let(:downstream_status) { 200 }
  let(:downstream_headers) { { "Content-Type" => "text/html; charset=utf-8" } }

  let(:downstream_app) do
    status = downstream_status
    headers = downstream_headers
    body = downstream_body
    ->(_env) { [status, headers.dup, [body]] }
  end

  let(:middleware) { described_class.new(downstream_app) }

  def with_enabled_wayback
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "README.md", "hi", message: "init")
      RailsWayback.enable!
      yield
    end
  end

  def response_header(headers, name)
    key = headers.keys.find { |candidate| candidate.to_s.casecmp?(name) }
    key ? headers[key] : nil
  end

  def call(path: "/letters", query: "", method: "GET")
    middleware.call(
      "PATH_INFO" => path,
      "QUERY_STRING" => query,
      "REQUEST_METHOD" => method
    )
  end

  context "when the gem is disabled" do
    it "leaves the response untouched" do
      SpecSupport.with_tmp_root do
        expect(RailsWayback.enabled?).to be(false)
        status, _headers, body = call
        expect(status).to eq(200)
        expect(body.join).to eq(downstream_body)
      end
    end
  end

  context "when the gem is enabled" do
    it "injects the bar into HTML responses" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        status, _headers, body = call
        expect(status).to eq(200)
        merged = body.join
        expect(merged).to include('id="rails-wayback-bar"')
        expect(merged).to include("</body>")
        expect(merged.index('id="rails-wayback-bar"')).to be < merged.index("</body>")
      end
    end

    it "skips non-HTML responses" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        allow(downstream_app).to receive(:call).and_return(
          [200, { "Content-Type" => "application/json" }, ['{"ok":true}']]
        )
        json_app = ->(_env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] }
        mw = described_class.new(json_app)
        _status, _headers, body = mw.call("PATH_INFO" => "/api/things", "QUERY_STRING" => "", "REQUEST_METHOD" => "GET")
        expect(body.join).to eq('{"ok":true}')
      end
    end

    it "skips paths under /rails-wayback and /assets" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        _status, _headers, body = call(path: "/rails-wayback/branches.json")
        expect(body.join).to eq(downstream_body)

        _status, _headers, body_assets = call(path: "/assets/application.css")
        expect(body_assets.join).to eq(downstream_body)
      end
    end

    it "owns and closes a request tracker without leaking its context" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        captured = nil
        capturing_app = lambda do |_env|
          captured = RailsWayback::RenderContext.current
          captured.record(event: "template", identifier: "/app/views/letters/index.html.erb")
          [200, { "Content-Type" => "text/html; charset=utf-8" }, [downstream_body]]
        end
        described_class.new(capturing_app).call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET"
        )

        expect(captured).to be_a(RailsWayback::RenderTracker)
        expect(captured.entries.size).to eq(1)
        expect(captured).to be_closed
        expect(RailsWayback::RenderContext.current).to be_nil
      end
    end

    it "closes the request tracker and clears its context when the app raises" do
      with_enabled_wayback do
        captured = nil
        failing_app = lambda do |_env|
          captured = RailsWayback::RenderContext.current
          raise "downstream failure"
        end
        failing_middleware = described_class.new(failing_app)

        expect do
          failing_middleware.call(
            "PATH_INFO" => "/letters",
            "QUERY_STRING" => "",
            "REQUEST_METHOD" => "GET"
          )
        end.to raise_error("downstream failure")

        expect(captured).to be_closed
        expect(RailsWayback::RenderContext.current).to be_nil
      end
    end

    it "renders a diff summary in the bar only when a ref is active" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!
        sha = RailsWayback::Git.new.current_commit

        _status, _headers, body = call(path: "/letters", query: "")
        expect(body.join).not_to include(%(<div class="rw-diff))

        _status, _headers, body_with_ref = call(
          path: "/letters",
          query: "_wayback_ref=#{sha}"
        )
        # The current commit is valid against itself, so the diff list is empty
        # but the neutral panel is still rendered.
        expect(body_with_ref.join).to include("rw-diff-neutral")
      end
    end

    it "reflects the traveling branch in the bar, preferring the explicit _wayback_branch param" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!
        sha = RailsWayback::Git.new.current_commit
        SpecSupport.run("git", "-C", root.to_s, "branch", "some-feature", sha)

        _status, _headers, body = call(
          path: "/letters",
          query: "_wayback_ref=#{sha}&_wayback_branch=some-feature"
        )
        merged = body.join
        expect(merged).to include('data-active-branch="some-feature"')
        # Labels flip to "Rendering ..." while a ref is active.
        expect(merged).to include(">Rendering ref<")
      end
    end

    it "keeps the travel active via cookies when the URL no longer carries the params" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!
        sha = RailsWayback::Git.new.current_commit
        SpecSupport.run("git", "-C", root.to_s, "branch", "feature-x", sha)

        _status, _headers, body = middleware.call(
          "PATH_INFO" => "/letters/42",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET",
          "HTTP_COOKIE" => "rails_wayback_ref=#{sha}; rails_wayback_branch=feature-x"
        )
        merged = body.join
        expect(merged).to include(%(data-active-ref="#{sha}"))
        expect(merged).to include('data-active-branch="feature-x"')
        expect(merged).to include(">Rendering ref<")
      end
    end

    it "gives precedence to the query param over the cookie when both are set" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!
        sha = RailsWayback::Git.new.current_commit
        SpecSupport.run("git", "-C", root.to_s, "branch", "from-url", sha)

        _status, _headers, body = middleware.call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "_wayback_ref=#{sha}&_wayback_branch=from-url",
          "REQUEST_METHOD" => "GET",
          "HTTP_COOKIE" => "rails_wayback_ref=OLD; rails_wayback_branch=from-cookie"
        )
        merged = body.join
        expect(merged).to include(%(data-active-ref="#{sha}"))
        expect(merged).to include('data-active-branch="from-url"')
      end
    end

    it "shows a trusted tag as the active ref label" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.configuration.trusted_ref_patterns = ["refs/heads/*", "refs/tags/*"]
        RailsWayback.enable!
        sha = RailsWayback::Git.new.current_commit
        SpecSupport.run("git", "-C", root.to_s, "tag", "preview", sha)

        _status, _headers, body = call(
          path: "/letters",
          query: "_wayback_ref=#{sha}&_wayback_branch=refs/tags/preview"
        )
        merged = body.join
        expect(merged).to include('data-active-branch="tag:preview"')
        expect(merged).to include(">Rendering ref<")
      end
    end

    it "repairs representation headers after injecting the bar" do
      with_enabled_wayback do
        original = downstream_body
        app = lambda do |_env|
          [
            200,
            {
              "Content-Type" => "text/html; charset=utf-8",
              "Content-Length" => original.bytesize.to_s,
              "ETag" => '"original"',
              "Content-MD5" => "original",
              "Digest" => "sha-256=original",
              "Content-Digest" => "sha-256=:original:",
              "Repr-Digest" => "sha-256=:original:",
              "Accept-Ranges" => "bytes",
              "Cache-Control" => "private"
            },
            [original]
          ]
        end

        _status, headers, body = described_class.new(app).call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET"
        )
        html = body.join

        expect(response_header(headers, "content-length")).to eq(html.bytesize.to_s)
        expect(response_header(headers, "cache-control")).to eq("private, no-store")
        expect(response_header(headers, "etag")).to be_nil
        expect(response_header(headers, "content-md5")).to be_nil
        expect(response_header(headers, "digest")).to be_nil
        expect(response_header(headers, "content-digest")).to be_nil
        expect(response_header(headers, "repr-digest")).to be_nil
        expect(response_header(headers, "accept-ranges")).to be_nil
      end
    end

    it "skips HEAD and unsafe response statuses" do
      with_enabled_wayback do
        aggregate_failures do
          _status, _headers, head_body = call(method: "HEAD")
          expect(head_body.join).to eq(downstream_body)

          [204, 205, 206].each do |status|
            app = ->(_env) { [status, downstream_headers.dup, [downstream_body]] }
            _response_status, _response_headers, body = described_class.new(app).call(
              "PATH_INFO" => "/letters",
              "QUERY_STRING" => "",
              "REQUEST_METHOD" => "GET"
            )
            expect(body.join).to eq(downstream_body)
          end
        end
      end
    end

    it "skips encoded, attached, transformed, ranged, and delegated responses" do
      unsafe_headers = [
        { "Content-Encoding" => "gzip" },
        { "Content-Encoding" => "br" },
        { "Content-Disposition" => 'attachment; filename="page.html"' },
        { "Cache-Control" => "private, no-transform" },
        { "Transfer-Encoding" => "chunked" },
        { "Content-Range" => "bytes 0-9/100" },
        { "X-Sendfile" => "/tmp/page.html" },
        { "X-Accel-Redirect" => "/internal/page.html" },
        { "rack.hijack" => ->(_stream) {} }
      ]

      with_enabled_wayback do
        aggregate_failures do
          unsafe_headers.each do |extra_headers|
            app = lambda do |_env|
              [200, downstream_headers.merge(extra_headers), [downstream_body]]
            end
            _status, _headers, body = described_class.new(app).call(
              "PATH_INFO" => "/letters",
              "QUERY_STRING" => "",
              "REQUEST_METHOD" => "GET"
            )
            expect(body.join).to eq(downstream_body)
          end
        end
      end
    end

    it "does not enumerate or close non-buffered response bodies" do
      enumerable_body = Class.new do
        attr_reader :enumerated, :closed

        def each
          @enumerated = true
          yield "<html><body>streamed</body></html>"
        end

        def close
          @closed = true
        end
      end.new
      callable_body = Class.new do
        attr_reader :called

        def call(_stream)
          @called = true
        end
      end.new

      with_enabled_wayback do
        aggregate_failures do
          [enumerable_body, callable_body].each do |source|
            app = ->(_env) { [200, downstream_headers.dup, source] }
            _status, _headers, returned = described_class.new(app).call(
              "PATH_INFO" => "/letters",
              "QUERY_STRING" => "",
              "REQUEST_METHOD" => "GET"
            )
            expect(returned).to equal(source)
          end

          expect(enumerable_body.enumerated).not_to be(true)
          expect(enumerable_body.closed).not_to be(true)
          expect(callable_body.called).not_to be(true)
        end
      end
    end

    it "leaves file-backed bodies untouched without materializing them" do
      file_body = Class.new do
        attr_reader :materialized

        def to_path
          "/tmp/example.html"
        end

        def to_ary
          @materialized = true
          ["<html><body>file</body></html>"]
        end
      end.new

      with_enabled_wayback do
        app = ->(_env) { [200, downstream_headers.dup, file_body] }
        _status, _headers, returned = described_class.new(app).call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET"
        )

        expect(returned).to equal(file_body)
        expect(file_body.materialized).not_to be(true)
      end
    end

    it "honors declared and actual response size limits" do
      declared_body = Class.new do
        attr_reader :materialized

        def to_ary
          @materialized = true
          ["<html><body>large</body></html>"]
        end
      end.new

      with_enabled_wayback do
        RailsWayback.configuration.max_response_bytes = 16
        declared_app = lambda do |_env|
          [200, downstream_headers.merge("Content-Length" => "100"), declared_body]
        end
        _status, _headers, returned = described_class.new(declared_app).call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET"
        )

        expect(returned).to equal(declared_body)
        expect(declared_body.materialized).not_to be(true)

        actual = ["<html><body>", "a" * 20, "</body></html>"]
        actual_app = ->(_env) { [200, downstream_headers.dup, actual] }
        _actual_status, _actual_headers, actual_returned = described_class.new(actual_app).call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET"
        )
        expect(actual_returned).to eq(actual)
        expect(actual_returned.join).not_to include('id="rails-wayback-bar"')
      end
    end

    it "skips HTML fragments, lookalike media types, and existing bars" do
      responses = [
        ["text/html", "<turbo-frame>Fragment</turbo-frame>"],
        ["application/text/html-json", downstream_body],
        ["text/html", '<html><body><div id="rails-wayback-bar"></div></body></html>']
      ]

      with_enabled_wayback do
        aggregate_failures do
          responses.each do |content_type, content|
            app = ->(_env) { [200, { "Content-Type" => content_type }, [content]] }
            _status, _headers, body = described_class.new(app).call(
              "PATH_INFO" => "/letters",
              "QUERY_STRING" => "",
              "REQUEST_METHOD" => "GET"
            )
            expect(body.join).to eq(content)
          end
        end
      end
    end

    it "is valid when wrapped with Rack::Lint" do
      with_enabled_wayback do
        app = lambda do |_env|
          [
            200,
            {
              "content-type" => "text/html; charset=utf-8",
              "content-length" => downstream_body.bytesize.to_s
            },
            [downstream_body]
          ]
        end
        stack = Rack::Lint.new(described_class.new(Rack::Lint.new(app)))

        response = Rack::MockRequest.new(stack).get("/letters")

        expect(response.status).to eq(200)
        expect(response.body).to include('id="rails-wayback-bar"')
      end
    end
  end
end
