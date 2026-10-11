# Repository Guidelines

## Project Structure & Module Organization
Dawarich is a Rails 8 monolith. Controllers, models, jobs, services, policies, and Stimulus/Turbo JS live in `app/`, while shared POROs sit in `lib/`. Configuration, credentials, and cron/Sidekiq settings live in `config/`; API documentation assets are in `swagger/`. Database migrations and seeds live in `db/`, Docker tooling sits in `docker/`, and docs or media live in `docs/` and `screenshots/`. Runtime artifacts in `storage/`, `tmp/`, and `log/` stay untracked.

## Architecture & Key Services
The stack pairs Rails 8 with PostgreSQL + PostGIS, Redis-backed Sidekiq, Devise/Pundit, Tailwind + DaisyUI, and MapLibre/Chartkick. Imports, exports, sharing, and trip analytics lean on PostGIS geometries plus workers, so queue anything non-trivial instead of blocking requests.

## Build, Test, and Development Commands
- `docker compose -f docker/docker-compose.yml up` — launches the full stack for smoke tests.
- `bundle exec rails db:prepare` — create/migrate the PostGIS database.
- `bundle exec bin/dev` and `bundle exec sidekiq` — start the web/Vite/Tailwind stack and workers locally.
- `make test` — runs Playwright (`npx playwright test e2e --workers=1`) then `bundle exec rspec`.
- `bundle exec rubocop` / `npx prettier --check app/javascript` — enforce formatting before commits.

## Coding Style & Naming Conventions
Use two-space indentation, snake_case filenames, and CamelCase classes. Keep Stimulus controllers under `app/javascript/controllers/*_controller.ts` so names match DOM `data-controller` hooks. Prefer service objects in `app/services/` for multi-step imports/exports, and let migrations named like `202405061210_add_indexes_to_events` manage schema changes. Follow Tailwind ordering conventions and avoid bespoke CSS unless necessary.

## Testing Guidelines
RSpec mirrors the app hierarchy inside `spec/` with files suffixed `_spec.rb`; rely on FactoryBot/FFaker for data, WebMock for HTTP, and SimpleCov for coverage. Browser journeys live in `e2e/` and should use `data-testid` selectors plus seeded demo data to reset state. Run `make test` before pushing and document intentional gaps when coverage dips.

## Commit & Pull Request Guidelines
Write short, imperative commit subjects (`Add globe_projection setting`) and include the PR/issue reference like `(#2138)` when relevant. Target `dev`, describe migrations, configs, and verification steps, and attach screenshots or curl examples for UI/API work. Link related Discussions for larger changes and request review from domain owners (imports, sharing, trips, etc.).

## Security & Configuration Tips
Start from `.env.example` or `.env.template` and store secrets in encrypted Rails credentials; never commit files from `gps-env/` or real trace data. Rotate API keys, scrub sensitive coordinates in fixtures, and use the synthetic traces in `db/seeds.rb` when demonstrating imports.


## Phoenix Native Frontend (milestone 7 implementation guidance)

`app-phoenix` is the native Phoenix application; root `app/` remains Rails. Read [native development](docs/phoenix/native-frontend-development.md), [architecture context](docs/phoenix/native-frontend-context.md) and [test successors](docs/phoenix/native-m7-test-retargets.md) for Phoenix work. These implementation instructions are finalized; release acceptance and the production runbook remain pending X4/X5. Rails workflows and lifecycle/Cloud defaults are unchanged.

Use the controller's targeted runner with private database/Redis and warnings-as-errors. Current Mix requires Elixir 1.20; the approved m7 runner supplies 1.20.4/OTP 27.3.4.1. Root `make test` is not the Phoenix gate. Full ExUnit needs an explicit FULL GATE brief and the controller's seedrun; standalone G44 runs at stage acceptance, not during implementation. New ExUnit modules are async unless they touch global state; record exceptions in the assigned plan.

Keep user behavior/data/security fixtures through named native successors. Contexts take `Accounts.Scope`; library hooks remain lazy and own teardown. Native forms, confirmations, local refusals and session boundaries must not regain Turbo/Stimulus islands, a controller registry or request-level Rails fallback. Merge A/B asset/routing deliveries before their final package acceptance: never delete root Rails asset sources or useful renderer/font/worker/data inputs based on a lexical scan. Protected lifecycle/entrypoint guards need a separate explicit brief.
