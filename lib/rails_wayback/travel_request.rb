# frozen_string_literal: true

require "action_dispatch"

module RailsWayback
  class TravelRequest
    REF_PARAM = "_wayback_ref"
    BRANCH_PARAM = "_wayback_branch"
    REF_COOKIE = "rails_wayback_ref"
    BRANCH_COOKIE = "rails_wayback_branch"

    def initialize(env)
      @request = ActionDispatch::Request.new(env)
    end

    def ref
      value(REF_PARAM, REF_COOKIE)
    end

    def branch
      value(BRANCH_PARAM, BRANCH_COOKIE)
    end

    def return_to
      query = request.query_parameters.except(REF_PARAM, BRANCH_PARAM).to_query
      query.empty? ? request.path : "#{request.path}?#{query}"
    end

    private

    attr_reader :request

    def value(param, cookie)
      parameter = request.query_parameters[param].to_s
      return parameter unless parameter.empty?

      cookie_value = request.cookies[cookie].to_s
      cookie_value unless cookie_value.empty?
    end
  end
end
