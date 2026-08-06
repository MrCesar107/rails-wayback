# frozen_string_literal: true

RailsWayback::Engine.routes.draw do
  # `format: false` keeps Rails from parsing a trailing `.json` as an
  # implicit format, and the glob `*branch` allows branch names that
  # contain slashes (e.g. "feature/foo"). The controller trims a
  # trailing `.json` defensively in case a client still appends it.
  get "branches", to: "pages#branches", format: false, as: :branches
  get "commits/*branch", to: "pages#commits", format: false, as: :commits
  get "reset", to: "pages#reset", format: false, as: :reset
end
