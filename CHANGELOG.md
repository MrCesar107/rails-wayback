# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- Restricted activation to the `development` and `test` environments by
  default, with an explicit `allowed_environments` configuration override.
- Kept render instrumentation inactive whenever Rails Wayback is disabled.

### Added

- Added `rails-wayback doctor` and `wayback:doctor` diagnostics for external
  tools, repository state, cache permissions, configured paths, and environment.
- Added RuboCop with Rails, Rake, and RSpec plugins, including local Rake tasks
  and a dedicated CI lint job.
- Added `/rails-wayback/reset` as a server-side recovery path that clears
  travel cookies without rendering host application views.
- Added provenance tracking for templates, partials, layouts, and collections,
  including toolbar warnings for mixed historical/current previews.

### Changed

- Raised the compatibility baseline to Ruby 3.3 and Rails 8.0.
- Added Appraisal dependency sets and a complete CI matrix for Ruby 3.3, 3.4,
  and 4.0 against Rails 8.0 and 8.1.
- Expanded real-Rails integration coverage for engine endpoints, travel request
  precedence, disabled behavior, response headers, and invalid references.
- Added install generator coverage for generated files and repeat-run
  idempotency.

### Fixed

- Served toolbar CSS and JavaScript as versioned same-origin engine resources,
  propagating Rails CSP nonces instead of requiring inline styles and scripts.
- Scoped render provenance to a request-owned, fiber-aware tracker so async
  rendering cannot leak or lose toolbar diagnostics across request contexts.
- Made toolbar injection Rack-compliant and limited it to complete, bounded,
  unencoded buffered HTML responses, preserving streaming, file, partial,
  attachment, and otherwise non-transformable responses.
- Made ref materialization transactional and concurrency-safe by validating the
  extraction pipeline, building in temporary directories, locking per ref, and
  coordinating cache cleanup with active builds.
- Made install generator duplicate checks respect the configured destination
  root instead of the invoking process's working directory.

## [0.1.1] - 2026-08-05

### Changed

- Extracted the toolbar HTML, CSS, and JavaScript from `BarRenderer` into
  dedicated packaged assets for easier maintenance.
- Scoped CLI activation to the current Rails server session. A new server now
  starts with Rails Wayback disabled while retaining runtime `on` and `off`
  commands without requiring a restart.
- Clarified the CLI output and documentation around activation lifetime.

## [0.1.0] - 2026-07-21

### Added

- Initial release of `rails-wayback`.
- Rails engine that renders any page as it looked on another branch or commit
  without touching the working tree.
- Overlay bar injected into every HTML response with branch/commit selectors,
  a diff summary panel, and Travel / Return-to-HEAD controls.
- `rails-wayback` CLI (`on`, `off`, `status`, `clean`) and equivalent
  `wayback:*` rake tasks to toggle the gem from the terminal.
- Persistent travel session backed by `rails_wayback_ref` and
  `rails_wayback_branch` cookies so internal navigations keep the traveled
  ref instead of falling back to the working tree.
- `RailsWayback::ViewSource` materialises historical `app/views` and
  `app/components` into `tmp/rails_wayback/refs/<sha>/` via
  `git archive | tar`.
- `RailsWayback::ControllerExtensions` prepends the materialised sandbox to
  the view paths on requests carrying the ref (URL param or cookie).
- Diff summary panel that surfaces which templates differ between the ref
  and HEAD and whether the current page actually renders any of them.
- Install generator (`bin/rails generate rails_wayback:install`) that wires
  a conditional mount into `config/routes.rb`, an optional initializer, and
  a `.gitignore` entry for `tmp/rails_wayback/`.

[Unreleased]: https://github.com/MrCesar107/rails-wayback/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/MrCesar107/rails-wayback/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/MrCesar107/rails-wayback/releases/tag/v0.1.0
