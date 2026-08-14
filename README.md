# rails-wayback

Preview and compare Rails UI across git branches and commits, directly in the
browser, from inside the developer's own Rails process. Toggle it on and off
from the terminal so it never gets in the way of normal development.

## Idea

When enabled, `rails-wayback` overlays a small bar at the bottom of every HTML
page of your app:

- Pick a branch and a commit.
- Hit **Travel**.
- The engine stores the authorized selection and reloads the current URL. The
  app renders that exact page using the **views/layouts/partials of the chosen
  ref**, while keeping the current controller's data and models.

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
bundle exec rails-wayback cache   # report ref cache usage and limits
bundle exec rails-wayback prune   # apply configured LRU cache limits
bundle exec rails-wayback clean   # drop the tmp/rails_wayback ref cache
bundle exec rails-wayback doctor  # check dependencies and app readiness
```

Same commands as rake tasks: `rake wayback:on`, `wayback:off`,
`wayback:status`, `wayback:cache`, `wayback:prune`, `wayback:clean`,
`wayback:doctor`.

Run `bin/rails wayback:doctor` from a Rails application to check Git and `tar`,
the repository root, cache write access, configured view and asset paths, and
the active Rails environment. Warnings do not fail the command; missing
dependencies or invalid runtime requirements return a non-zero exit status.

Activation lasts for the current Rails server session. Every new server start
begins with `rails-wayback` disabled, while `on` and `off` can still be used at
any time without restarting Rails.

With the gem enabled, load any page of your app. A dark bar appears at the
bottom with:

- `Current ref` — dropdown of trusted branches, remote-tracking branches, and
  tags already stored in the local repository. Its search box filters the
  loaded refs by name, label, or type.
- `Current commit` — dropdown of the recent commits on that ref. Its search
  box filters the loaded commits by SHA, subject, author, or date.
- `Travel` — reloads the current URL using views from that commit.
- `Return to HEAD` — appears while traveling; goes back to live views.
  It submits to the engine's server-owned travel resource, which clears the
  travel cookies before redirecting back to the current page. Historical
  template failures render the same self-contained recovery form.

There is no dedicated `/rails-wayback` page. The gem stays quiet on assets,
ActionCable, and every URL under `/rails-wayback` (used by the bar to fetch Git
data and manage travel state). The toolbar renders native ref and commit
selectors first, so travel and recovery remain usable without JavaScript.
JavaScript progressively upgrades those controls with search and keyboard
navigation when the engine endpoints are available.

## How "travel" actually works

`rails-wayback` never runs a second Rails server. Travel is just:

1. The bar posts the selected ref to the engine's travel controller.
2. The controller authorizes the commit, stores the canonical ref in HTTP-only
   same-site cookies, and redirects back to the original URL.
3. A `before_action`, auto-included in every `ActionController::Base`
   subclass, sees `_wayback_ref` and materialises that ref under
   `tmp/rails_wayback/refs/<sha>/` (cached per commit).
   Shared URLs carrying `_wayback_ref` remain supported, with query parameters
   taking precedence over cookies.
4. The same before_action calls `prepend_view_path` with the sandbox, so
   Action View resolves templates from the ref before falling back to the
   current tree.
5. Standard Rails asset helpers resolve browser-ready files from the ref's
   `public/` directory to immutable, SHA-specific engine URLs. Missing files
   fall back to the current Rails asset resolver.
6. Your controller runs as usual, sets its `@` variables, and renders. The
   visual layer (layouts, partials, ERB) comes from the past; the data and
   business logic come from the present.

If a historical template references a helper, assign, model attribute, or
database state that no longer exists, Rails Wayback returns a self-contained
500 recovery page with the original error and a **Return to current version**
action. This boundary applies only when the failing template came from the
materialised historical ref; unrelated controller and application errors keep
their normal Rails behavior. The recovery response contains an isolated,
CSRF-protected form that clears travel state without rendering another host
application view.

The toolbar tracks templates, partials, layouts, and collections. While
traveling it labels a response as historical, current fallback, or mixed so
you can tell when Rails filled a missing historical file from the current
view tree. It also reports historical public assets and current asset
fallbacks discovered through standard Rails helpers.

### Historical public assets

While traveling, existing calls to `asset_path`, `image_tag`,
`stylesheet_link_tag`, `javascript_include_tag`, and the other standard Rails
asset helpers automatically look for browser-ready files in the selected
commit's `public/` directory. A historical file is served from a URL such as
`/rails-wayback/refs/<sha>/assets/images/logo.svg`; the SHA prevents browser
and proxy caches from mixing revisions. Asset responses reauthorize the ref,
reject unsafe paths and escaping symlinks, use immutable caching, and keep a
cache lease for the complete streamed response.

If a public file is absent, the normal current Rails resolver remains the
fallback and the toolbar reports it. Direct hard-coded URLs such as
`/assets/application.css` bypass Rails helpers and are not rewritten.
Historical Propshaft/Sprockets compilation, Sass or TypeScript processing,
import maps, and JavaScript/CSS bundlers are not reproduced yet; `app/assets`
continues to be extracted for comparison but is not served by this initial
static-file strategy.

## Configuration (optional)

`config/initializers/rails_wayback.rb`:

```ruby
RailsWayback.configure do |config|
  # config.allowed_environments = %w[development test]
  # config.trusted_ref_patterns = ["refs/heads/*"]
  # config.view_paths  = %w[app/views]
  # config.asset_paths = %w[app/assets public]
  # config.max_commits = 50
  # config.max_cached_refs = 25
  # config.max_cache_bytes = 512 * 1024 * 1024
  # config.max_response_bytes = 2 * 1024 * 1024
end
```

Rails Wayback refuses to activate outside `development` and `test` by
default, even if its toggle file exists. Adding another environment is an
explicit opt-in; historical templates execute inside the host Rails process,
so only trusted refs should be used. Travel accepts only full commit SHAs and,
by default, the commit must be reachable from a local branch. Narrow
`trusted_ref_patterns` to branches such as `refs/heads/main` or
`refs/heads/release/*`, or explicitly add locally stored remote-tracking refs
and tags:

```ruby
config.trusted_ref_patterns = [
  "refs/heads/*",
  "refs/remotes/origin/review/*",
  "refs/tags/preview-*"
]
```

Matching refs appear in the toolbar and can be used for commit discovery.
Ref and commit search is performed in the browser over the data already loaded
by the toolbar; commit search is therefore limited to `max_commits` entries for
the selected ref and does not run additional Git commands or network requests.
Rails Wayback never runs `git fetch`: remote-tracking refs must already exist
locally, symbolic aliases such as `origin/HEAD` are omitted, and untrusted refs
cannot be queried through the commits endpoint. Detached commits remain blocked.

This policy reduces accidental execution but is not a sandbox. Historical ERB
and other executable template handlers run with the Rails server's filesystem,
database, credentials, environment, and network permissions. Historical
JavaScript also executes in the browser under the development application's
origin. The toolbar shows a permanent warning and asks for confirmation on the
first travel action in each browser session. The response-size limit applies only to
toolbar injection; streaming, encoded, file, partial, and larger responses are
returned untouched. Toolbar CSS and JavaScript are served from the mounted
engine, so CSP policies should allow same-origin styles, scripts, and fetches.
Rails-generated CSP nonces are copied to both asset tags automatically.
Everything above has a sensible default. Delete the initializer if you don't
need to change anything.

Cached refs use least-recently-used access metadata. After materialising a new
ref, Rails Wayback automatically removes the oldest refs until the configured
count and byte limits are met. A shared cache lease protects each ref for the
complete historical render, so automatic or manual `prune` and `clean`
operations wait for active previews before removing their files.
`rails-wayback cache` reports logical payload size and file count, while
`rails-wayback prune` applies the limits immediately. `rails-wayback clean`
removes all ref data and per-ref lock files. Set either cache limit to `nil` to
disable it.

## Supported public API

Rails Wayback deliberately keeps its Ruby extension surface small. Semantic
versioning applies to these entry points:

- `require "rails_wayback"` and `RailsWayback::VERSION`.
- `RailsWayback.configure`, `RailsWayback.configuration`,
  `RailsWayback.enabled?`, `RailsWayback.enable!`, and
  `RailsWayback.disable!`. Calling `enable!` in a disallowed environment may
  raise `RailsWayback::DisabledError`.
- The documented configuration attributes: `allowed_environments`,
  `trusted_ref_patterns`, `view_paths`, `asset_paths`, `max_commits`,
  `max_cached_refs`, `max_cache_bytes`, and `max_response_bytes`.
- `RailsWayback::Engine`, the `rails_wayback:install` generator, the
  `rails-wayback` executable commands, and their documented `wayback:*` Rake
  task equivalents.

The initializer configuration block is the supported extension point. The
engine controllers and HTTP endpoints, middleware, toolbar state, Git wrapper,
cache implementation, renderer, and other constants under `RailsWayback` are
internal. They may change between minor releases and should not be
monkey-patched or called by application code. In particular, the JSON endpoints
under the engine mount support the packaged toolbar; they are not a general
remote Git API. There are currently no supported callbacks or adapter
interfaces beyond configuration.

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
