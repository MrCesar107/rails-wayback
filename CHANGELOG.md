# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/MrCesar107/rails-wayback/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MrCesar107/rails-wayback/releases/tag/v0.1.0
