# Repository Guidelines

## Project Structure & Module Organization
- `app/` holds the Rails application: controllers and views under feature-oriented folders, `services/` for importers and background workflows, and `policies/` for Pundit authorization.
- `app/javascript/` contains Stimulus controllers (`controllers/`), map widgets (`maps/`), and Tailwind/Turbo setup in `application.js`.
- `lib/` stores reusable support code and rake tasks, while `config/` tracks environment settings, credentials, and initializers.
- `db/` carries schema migrations and data migrations; `spec/` provides RSpec coverage; `e2e/` hosts Playwright scenarios; `docker/` bundles deployment compose files.

## Build, Test, and Development Commands
- `bundle exec rails db:prepare` initializes or migrates the PostgreSQL database.
- `bundle exec bin/dev` starts the Rails app plus JS bundler via Foreman using `Procfile.dev` (set `PROMETHEUS_EXPORTER_ENABLED=true` to use the Prometheus profile).
- `bundle exec sidekiq` runs background jobs locally alongside the web server.
- `docker compose -f docker/docker-compose.yml up` brings up the containerized stack for end-to-end smoke checks.

## Coding Style & Naming Conventions
- Follow default Ruby style with two-space indentation and snake_case filenames; run `bin/rubocop` before pushing.
- JavaScript modules in `app/javascript/` use ES modules and Stimulus naming (`*_controller.js`); keep exports camelCase and limit files to a single controller.
- Tailwind classes power the UI; co-locate shared styles under `app/javascript/styles/` rather than inline overrides.

## Testing Guidelines
- Use `bundle exec rspec` for unit and feature specs; mirror production behavior by tagging jobs or services with factories in `spec/support`.
- End-to-end flows live in `e2e/`; execute `npx playwright test` (set `BASE_URL` if the server runs on a non-default port).
- Commit failing scenarios together with the fix, and prefer descriptive `it "..."` strings that capture user intent.

## Commit & Pull Request Guidelines
- Write concise, imperative commit titles (e.g., `Add family sharing policy`); group related changes rather than omnibus commits.
- Target pull requests at the `dev` branch, describe the motivation, reference GitHub issues when applicable, and attach screenshots for UI-facing changes.
- Confirm CI, lint, and test status before requesting review; call out migrations or data tasks in the PR checklist.

## Environment & Configuration Tips
- Copy `.env.example` to `.env` or rely on Docker secrets to supply API keys, map tokens, and mail credentials.
- Regenerate credentials with `bin/rails credentials:edit` when altering secrets, and avoid committing any generated `.env` or `credentials.yml.enc` changes.
