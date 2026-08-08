# frozen_string_literal: true

RailsWayback::Engine.routes.draw do
  get "assets/bar.css", to: "assets#stylesheet", format: false, as: :bar_stylesheet
  get "assets/bar.js", to: "assets#javascript", format: false, as: :bar_javascript
  get "refs/:sha/assets/*path", to: "assets#historical", format: false, as: :historical_asset

  # `format: false` keeps Rails from parsing a trailing `.json` as an
  # implicit format, and the glob `*branch` allows branch names that
  # contain slashes (e.g. "feature/foo"). The controller trims a
  # trailing `.json` defensively in case a client still appends it.
  get "branches", to: "pages#branches", format: false, as: :branches
  get "commits/*branch", to: "pages#commits", format: false, as: :commits
  get "reset", to: "pages#reset", format: false, as: :reset
end
