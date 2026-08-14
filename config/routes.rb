# frozen_string_literal: true

RailsWayback::Engine.routes.draw do
  get "assets/bar.css", to: "assets#stylesheet", format: false, as: :bar_stylesheet
  get "assets/bar.js", to: "assets#javascript", format: false, as: :bar_javascript
  get "refs/:sha/assets/*path", to: "assets#historical", format: false, as: :historical_asset

  resources :references, only: :index
  resources :commits, only: :index
  resource :travel, only: %i[create destroy]
end
