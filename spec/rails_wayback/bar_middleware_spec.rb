# frozen_string_literal: true

require "rails_wayback/bar_middleware"

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

  def call(path: "/letters", query: "")
    middleware.call(
      "PATH_INFO" => path,
      "QUERY_STRING" => query,
      "REQUEST_METHOD" => "GET"
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

    it "resets the per-request render tracker before invoking the app" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        Thread.current[RailsWayback::RENDER_TRACKER_KEY] = ["stale/from/previous/request.html.erb"]

        observed = nil
        capturing_app = lambda do |_env|
          observed = Thread.current[RailsWayback::RENDER_TRACKER_KEY].dup
          [200, { "Content-Type" => "text/html; charset=utf-8" }, [downstream_body]]
        end
        described_class.new(capturing_app).call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET"
        )

        expect(observed).to eq([])
      end
    end

    it "renders a diff summary in the bar only when a ref is active" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        _status, _headers, body = call(path: "/letters", query: "")
        expect(body.join).not_to include(%(<div class="rw-diff))

        _status, _headers, body_with_ref = call(
          path: "/letters",
          query: "_wayback_ref=HEAD"
        )
        # HEAD is a valid ref against itself, so the diff list is empty
        # but the neutral panel is still rendered.
        expect(body_with_ref.join).to include("rw-diff-neutral")
      end
    end

    it "reflects the traveling branch in the bar, preferring the explicit _wayback_branch param" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        _status, _headers, body = call(
          path: "/letters",
          query: "_wayback_ref=HEAD&_wayback_branch=some-feature"
        )
        merged = body.join
        expect(merged).to include('data-active-branch="some-feature"')
        # Labels flip to "Rendering ..." while a ref is active.
        expect(merged).to include(">Rendering branch<")
      end
    end

    it "keeps the travel active via cookies when the URL no longer carries the params" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        _status, _headers, body = middleware.call(
          "PATH_INFO" => "/letters/42",
          "QUERY_STRING" => "",
          "REQUEST_METHOD" => "GET",
          "HTTP_COOKIE" => "rails_wayback_ref=HEAD; rails_wayback_branch=feature-x"
        )
        merged = body.join
        expect(merged).to include('data-active-ref="HEAD"')
        expect(merged).to include('data-active-branch="feature-x"')
        expect(merged).to include(">Rendering branch<")
      end
    end

    it "gives precedence to the query param over the cookie when both are set" do
      SpecSupport.with_tmp_root do |root|
        SpecSupport.build_git_repo(root)
        SpecSupport.commit_file(root, "README.md", "hi", message: "init")
        RailsWayback.enable!

        _status, _headers, body = middleware.call(
          "PATH_INFO" => "/letters",
          "QUERY_STRING" => "_wayback_ref=HEAD&_wayback_branch=from-url",
          "REQUEST_METHOD" => "GET",
          "HTTP_COOKIE" => "rails_wayback_ref=OLD; rails_wayback_branch=from-cookie"
        )
        merged = body.join
        expect(merged).to include('data-active-ref="HEAD"')
        expect(merged).to include('data-active-branch="from-url"')
      end
    end
  end
end
