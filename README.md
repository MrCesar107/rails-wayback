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
```

Same commands as rake tasks: `rake wayback:on`, `wayback:off`,
`wayback:status`, `wayback:clean`.

With the gem enabled, load any page of your app. A dark bar appears at the
bottom with:

- `Current branch` — dropdown of your local branches.
- `Current commit` — dropdown of the recent commits on that branch.
- `Travel` — reloads the current URL using views from that commit.
- `Return to HEAD` — appears while traveling; goes back to live views.

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
piece — the app itself never changes.

## Configuration (optional)

`config/initializers/rails_wayback.rb`:

```ruby
RailsWayback.configure do |config|
  # config.view_paths  = %w[app/views]
  # config.asset_paths = %w[app/assets public]
  # config.max_commits = 50
end
```

Everything above has a sensible default. Delete the initializer if you
don't need to change anything.

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT
