# rails-wayback

Preview and compare Rails UI across git branches and commits, directly in the
browser, from inside the developer's own Rails process. Toggle it on and off
from the terminal so it never gets in the way of normal development.

## Idea

When enabled, `rails-wayback` overlays a small bar at the bottom of every HTML
page of your app:

- Pick a branch and a commit.
- Hit **Travel**.
- The current URL reloads with `?_wayback_ref=<sha>`, and the app renders
  that exact page using the **views/layouts/partials of the chosen ref**,
  while keeping the current controller's data and models.

Design goals:

- **Zero configuration.** Drop the gem in, run the installer, turn it on.
- **One process only.** Uses the running dev app — no extra Rails server.
- **HTML render, not screenshots.**
- **Toggleable from the CLI.** Stays inert when you don't need it.

## Install

Add the gem to the host app's `Gemfile`, in the development group:

```ruby
group :development do
  gem "rails-wayback"
end
```

Then run the installer:

```bash
bin/rails generate rails_wayback:install
```

That adds a conditional mount to `config/routes.rb`, an initializer at
`config/initializers/rails_wayback.rb` (optional overrides), and a
`.gitignore` entry for `tmp/rails_wayback/`.

## Usage

Turn the UI on when you need it, off when you don't:

```bash
bundle exec rails-wayback on      # enable and inject the bar in every page
bundle exec rails-wayback off     # disable it
bundle exec rails-wayback status  # print current state
bundle exec rails-wayback clean   # drop the tmp/rails_wayback ref cache
bundle exec rails-wayback doctor  # check dependencies and app readiness
```

Same commands as rake tasks: `rake wayback:on`, `wayback:off`,
`wayback:status`, `wayback:clean`, `wayback:doctor`.

Run `bin/rails wayback:doctor` from a Rails application to check Git and `tar`,
the repository root, cache write access, configured view and asset paths, and
the active Rails environment. Warnings do not fail the command; missing
dependencies or invalid runtime requirements return a non-zero exit status.

Activation lasts for the current Rails server session. Every new server start
begins with `rails-wayback` disabled, while `on` and `off` can still be used at
any time without restarting Rails.

With the gem enabled, load any page of your app. A dark bar appears at the
bottom with:

- `Current branch` — dropdown of your local branches.
- `Current commit` — dropdown of the recent commits on that branch.
- `Travel` — reloads the current URL using views from that commit.
- `Return to HEAD` — appears while traveling; goes back to live views.
  It uses a server-side reset endpoint, which is also available directly at
  `/rails-wayback/reset` if a historical template prevents the page from
  rendering.

There is no dedicated `/rails-wayback` page. The gem stays quiet on assets,
ActionCable, and every URL under `/rails-wayback/*.json` (used by the bar to
fetch git data).

## How "travel" actually works

`rails-wayback` never runs a second Rails server. Travel is just:

1. The bar appends `?_wayback_ref=<sha>` to the current URL and reloads.
2. A `before_action`, auto-included in every `ActionController::Base`
   subclass, sees `_wayback_ref` and materialises that ref under
   `tmp/rails_wayback/refs/<sha>/` (cached per commit).
3. The same before_action calls `prepend_view_path` with the sandbox, so
   Action View resolves templates from the ref before falling back to the
   current tree.
4. Your controller runs as usual, sets its `@` variables, and renders. The
   visual layer (layouts, partials, ERB) comes from the past; the data and
   business logic come from the present.

If a historical template references a helper or assign that no longer
exists, you'll get the same `ActionView` error you'd get from any missing
piece — the app itself never changes. Open `/rails-wayback/reset` to clear the
travel cookies if that error prevents the toolbar from rendering.

The toolbar tracks templates, partials, layouts, and collections. While
traveling it labels a response as historical, current fallback, or mixed so
you can tell when Rails filled a missing historical file from the current
view tree.

## Configuration (optional)

`config/initializers/rails_wayback.rb`:

```ruby
RailsWayback.configure do |config|
  # config.allowed_environments = %w[development test]
  # config.view_paths  = %w[app/views]
  # config.asset_paths = %w[app/assets public]
  # config.max_commits = 50
  # config.max_response_bytes = 2 * 1024 * 1024
end
```

Rails Wayback refuses to activate outside `development` and `test` by
default, even if its toggle file exists. Adding another environment is an
explicit opt-in; historical templates execute inside the host Rails process,
so only trusted refs should be used. The response-size limit applies only to
toolbar injection; streaming, encoded, file, partial, and larger responses are
returned untouched. Toolbar CSS and JavaScript are served from the mounted
engine, so CSP policies should allow same-origin styles, scripts, and fetches.
Rails-generated CSP nonces are copied to both asset tags automatically.
Everything above has a sensible default. Delete the initializer if you don't
need to change anything.

## Compatibility

Rails Wayback requires Ruby 3.3 or newer and Rails 8.0 or newer. CI runs the
complete matrix of Ruby 3.3, 3.4, and 4.0 against Rails 8.0 and 8.1.
Compatibility here means that the gem's suite passes on that combination; it
does not extend the upstream maintenance or security lifetime of Ruby or Rails.

## Development

```bash
bundle install
bundle exec rspec
```

Rails dependency sets are managed with Appraisal. Regenerate their Gemfiles
after changing `Appraisals`, then run an individual Rails line with:

```bash
bundle exec appraisal generate
bundle exec appraisal rails-8-0 rspec
```

## Release

Releases are cut by pushing an annotated `vX.Y.Z` git tag. GitHub Actions runs
the specs and pushes the gem to RubyGems using
[Trusted Publishing (OIDC)](https://guides.rubygems.org/trusted-publishing/),
so there are no API tokens stored on GitHub and MFA on the RubyGems account is
never in the way.

### One-time setup

1. On GitHub, go to **Settings → Environments → New environment** and create
   an environment named exactly `release`. (Optionally add branch protection
   so only `main` and tags can deploy to it.)
2. On [rubygems.org](https://rubygems.org):
   - For the very first release, go to **Profile → Trusted publishers →
     Pending trusted publishers → Create** and fill in:
     - RubyGem name: `rails-wayback`
     - Repository owner: `MrCesar107`
     - Repository name: `rails-wayback`
     - Workflow filename: `release.yml`
     - Environment: `release`
   - For every release after 0.1.0, the pending publisher is promoted to a
     normal trusted publisher automatically — nothing to configure again.
3. Make sure MFA is enabled on your RubyGems account (the gemspec sets
   `rubygems_mfa_required = true`).

### Cutting a release

1. Update `lib/rails_wayback/version.rb` following
   [SemVer](https://semver.org/spec/v2.0.0.html).
2. Move the pending entries in `CHANGELOG.md` from `[Unreleased]` into a new
   `[X.Y.Z] - YYYY-MM-DD` section and update the compare/tag links at the
   bottom of the file.
3. Commit both files:
   ```bash
   git commit -am "Release vX.Y.Z"
   ```
4. Tag and push:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin main --follow-tags
   ```
5. Watch the `Release` workflow on GitHub. It refuses to publish if the tag
   doesn't match `RailsWayback::VERSION`, so a typo in the tag will fail
   loudly before touching RubyGems.

### Manual fallback

If the workflow is broken and you need to publish from your laptop:

```bash
gem build rails-wayback.gemspec
gem push rails-wayback-X.Y.Z.gem
```

`gem push` will ask for your RubyGems credentials and MFA code the first
time.

## License

MIT
