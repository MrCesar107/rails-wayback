# frozen_string_literal: true

module RailsWayback
  # Exposes the request-owned render tracker to notification callbacks.
  # Ruby fiber storage is inherited by child fibers and scoped separately
  # for sibling fibers, which matches the lifecycle of async Rack requests.
  module RenderContext
    KEY = :rails_wayback_render_tracker

    module_function

    def current
      Fiber[KEY]
    end

    def with(tracker)
      previous = current
      Fiber[KEY] = tracker
      yield
    ensure
      Fiber[KEY] = previous
    end
  end
end
