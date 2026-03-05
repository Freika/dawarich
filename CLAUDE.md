# CLAUDE.md - Dawarich Development Guide

This file contains essential information for Claude to work effectively with the Dawarich codebase.

## Project Overview

**Dawarich** is a self-hostable web application built with Ruby on Rails 8.0 that serves as a replacement for Google Timeline (Google Location History). It allows users to track, visualize, and analyze their location data through an interactive web interface.

### Key Features
- Location history tracking and visualization
- Interactive maps with multiple layers (heatmap, points, lines, fog of war)
- Import from various sources (Google Maps Timeline, OwnTracks, Strava, GPX, GeoJSON, photos)
- Export to GeoJSON and GPX formats
- Statistics and analytics (countries visited, distance traveled, etc.)
- Public sharing of monthly statistics with time-based expiration
- Trips management with photo integration
- Areas and visits tracking
- Integration with photo management systems (Immich, Photoprism)

## Technology Stack

### Backend
- **Framework**: Ruby on Rails 8.0
- **Database**: PostgreSQL with PostGIS extension
- **Background Jobs**: Sidekiq with Redis
- **Authentication**: Devise
- **Authorization**: Pundit
- **API Documentation**: rSwag (Swagger)
- **Monitoring**: Prometheus, Sentry
- **File Processing**: AWS S3 integration

### Frontend
- **CSS Framework**: Tailwind CSS with DaisyUI components
- **JavaScript**: Stimulus, Turbo Rails, Hotwired
- **Maps**: Leaflet.js
- **Charts**: Chartkick

### Key Gems
- `activerecord-postgis-adapter` - PostgreSQL PostGIS support
- `geocoder` - Geocoding services
- `rgeo` - Ruby Geometric Library
- `gpx` - GPX file processing
- `parallel` - Parallel processing
- `sidekiq` - Background job processing
- `chartkick` - Chart generation

## Project Structure

```
├── app/
│   ├── controllers/     # Rails controllers
│   ├── models/         # ActiveRecord models with PostGIS support
│   ├── views/          # ERB templates
│   ├── services/       # Business logic services
│   ├── jobs/           # Sidekiq background jobs
│   ├── queries/        # Database query objects
│   ├── policies/       # Pundit authorization policies
│   ├── serializers/    # API response serializers
│   ├── javascript/     # Stimulus controllers and JS
│   └── assets/         # CSS and static assets
├── config/             # Rails configuration
├── db/                 # Database migrations and seeds
├── docker/             # Docker configuration
├── spec/               # RSpec test suite
└── swagger/            # API documentation
```

## Core Models

### Primary Models
- **User**: Authentication and user management
- **Point**: Individual location points with coordinates and timestamps
- **Track**: Collections of related points forming routes
- **Area**: Geographic areas drawn by users
- **Visit**: Detected visits to areas
- **Trip**: User-defined travel periods with analytics
- **Import**: Data import operations
- **Export**: Data export operations
- **Stat**: Calculated statistics and metrics with public sharing capabilities

### Geographic Features
- Uses PostGIS for advanced geographic queries
- Implements distance calculations and spatial relationships
- Supports various coordinate systems and projections

## Development Environment

### Setup
1. **Docker Development**: Use `docker-compose -f docker/docker-compose.yml up`
2. **DevContainer**: VS Code devcontainer support available
3. **Local Development**:
   - `bundle exec rails db:prepare`
   - `bundle exec sidekiq` (background jobs)
   - `bundle exec bin/dev` (main application)

### Default Credentials
- Username: `demo@dawarich.app`
- Password: `password`

## Testing

### Test Suite
- **Framework**: RSpec
- **System Tests**: Capybara + Selenium WebDriver
- **E2E Tests**: Playwright
- **Coverage**: SimpleCov
- **Factories**: FactoryBot
- **Mocking**: WebMock

### Test Commands
```bash
bundle exec rspec                    # Run all specs
bundle exec rspec spec/models/       # Model specs only
npx playwright test                  # E2E tests
```

### Testing Best Practices — Test Behavior, Not Implementation

When writing or modifying tests, always test **observable behavior** (return values, state changes, side effects) rather than **implementation details** (which internal methods are called, in what order, with what exact arguments).

**Anti-patterns to AVOID:**

1. **Never mock the object under test** — `allow(subject).to receive(:internal_method)` makes the test a tautology
2. **Never test private methods via `send()`** — test through the public interface instead; if creating a user triggers a trial, test by creating the user and checking `user.trial?`, not by calling `user.send(:start_trial)`
3. **Never use `receive_message_chain`** — `allow(x).to receive_message_chain(:a, :b, :c)` breaks on any scope reorder; use real data instead
4. **Avoid over-stubbing** — if every collaborator is mocked, the test proves nothing; mock only at external boundaries (HTTP, geocoder, external APIs)
5. **Don't test wiring without outcomes** — `expect(Service).to receive(:new).with(args)` only proves a method was called, not that it works; verify the returned data or state change instead
6. **Prefer `have_enqueued_job` over `expect(Job).to receive(:perform_later)`** — the former tests real ActiveJob integration; the latter just tests a mock
7. **Don't assert on cache key formats or internal metric JSON shapes** — test that caching works (2nd call doesn't requery) or that metrics fire, not exact internal formats
8. **Use real factory data over `allow(user).to receive(:active?).and_return(true)`** — set the actual user state: `create(:user, status: :active)`

**Good test pattern:**
```ruby
# Test behavior: creating an export enqueues processing
it 'enqueues processing job' do
  expect { create(:export, file_type: :points) }.to have_enqueued_job(ExportJob)
end
```

**Bad test pattern:**
```ruby
# Tests implementation: mocks the callback interaction
it 'enqueues processing job' do
  expect(ExportJob).to receive(:perform_later)  # mock, not real
  build(:export).save!
end
```

## Background Jobs

### Sidekiq Jobs
- **Import Jobs**: Process uploaded location data files
- **Calculation Jobs**: Generate statistics and analytics
- **Notification Jobs**: Send user notifications
- **Photo Processing**: Extract EXIF data from photos

### Key Job Classes
- `Tracks::ParallelGeneratorJob` - Generate track data in parallel
- Various import jobs for different data sources
- Statistical calculation jobs

## Public Sharing System

### Overview
Dawarich includes a comprehensive public sharing system that allows users to share their monthly statistics with others without requiring authentication. This feature enables users to showcase their location data while maintaining privacy control through configurable expiration settings.

### Key Features
- **Time-based expiration**: Share links can expire after 1 hour, 12 hours, 24 hours, or be permanent
- **UUID-based access**: Each shared stat has a unique, unguessable UUID for security
- **Public API endpoints**: Hexagon map data can be accessed via API without authentication when sharing is enabled
- **Automatic cleanup**: Expired shares are automatically inaccessible
- **Privacy controls**: Users can enable/disable sharing and regenerate sharing URLs at any time

### Technical Implementation
- **Database**: `sharing_settings` (JSONB) and `sharing_uuid` (UUID) columns on `stats` table
- **Routes**: `/shared/month/:uuid` for public viewing, `/stats/:year/:month/sharing` for management
- **API**: `/api/v1/maps/hexagons` supports public access via `uuid` parameter
- **Controllers**: `Shared::StatsController` handles public views, sharing management integrated into existing stats flow

### Security Features
- **No authentication bypass**: Public sharing only exposes specifically designed endpoints
- **UUID-based access**: Sharing URLs use unguessable UUIDs rather than sequential IDs
- **Expiration enforcement**: Automatic expiration checking prevents access to expired shares
- **Limited data exposure**: Only monthly statistics and hexagon data are publicly accessible

### Usage Patterns
- **Social sharing**: Users can share interesting travel months with friends and family
- **Portfolio/showcase**: Travel bloggers and photographers can showcase location statistics
- **Data collaboration**: Researchers can share aggregated location data for analysis
- **Public demonstrations**: Demo instances can provide public examples without compromising user data

## API Documentation

- **Framework**: rSwag (Swagger/OpenAPI)
- **Location**: `/api-docs` endpoint
- **Authentication**: API key (Bearer) for API access, UUID-based access for public shares

## Database Schema

### Key Tables
- `users` - User accounts and settings
- `points` - Location points with PostGIS geometry
- `tracks` - Route collections
- `areas` - User-defined geographic areas
- `visits` - Detected area visits
- `trips` - Travel periods
- `imports`/`exports` - Data transfer operations
- `stats` - Calculated metrics with sharing capabilities (`sharing_settings`, `sharing_uuid`)

### PostGIS Integration
- Extensive use of PostGIS geometry types
- Spatial indexes for performance
- Geographic calculations and queries

## Configuration

### Environment Variables
See `.env.template` for available configuration options including:
- Database configuration
- Redis settings
- AWS S3 credentials
- External service integrations
- Feature flags

### Key Config Files
- `config/database.yml` - Database configuration
- `config/sidekiq.yml` - Background job settings
- `config/schedule.yml` - Cron job schedules
- `docker/docker-compose.yml` - Development environment

## Deployment

### Docker
- Production: `docker/docker-compose.production.yml`
- Development: `docker/docker-compose.yml`
- Multi-stage Docker builds supported

### Procfiles
- `Procfile` - Production Heroku deployment
- `Procfile.dev` - Development with Foreman
- `Procfile.production` - Production processes

## Code Quality

### Tools
- **Ruby Linting**: RuboCop with Rails extensions
- **JS/CSS Linting**: Biome (formatting, lint, import sorting)
- **Security**: Brakeman, bundler-audit
- **Dependencies**: Strong Migrations for safe database changes
- **Performance**: Stackprof for profiling

### Commands
```bash
bundle exec rubocop                  # Ruby linting
npx @biomejs/biome check --write .   # JS/CSS auto-fix (safe fixes)
npx @biomejs/biome check --write --unsafe .  # JS/CSS auto-fix (all fixes)
npx @biomejs/biome ci .              # JS/CSS CI check (read-only)
bundle exec brakeman                 # Security scan
bundle exec bundle-audit             # Dependency security
```

### Lint Rules
- **Always run RuboCop** on modified Ruby files before committing: `bundle exec rubocop <files>`
- **Always run Biome** on modified JS/CSS files before committing: `npx @biomejs/biome check --write <files>`
- If Biome `--write` leaves remaining errors, use `--write --unsafe` to apply fixes like `parseInt` radix and `Number.isNaN`
- CI runs `biome ci --changed --since=dev` — it compares against the `dev` branch, not `master`
- The `noStaticOnlyClass` warning is acceptable and does not fail CI
- Tailwind CSS files (`*.tailwind.css`) have `@import` position rules disabled in `biome.json` because `@tailwind` directives must come first

## Frontend: Hotwire-First Approach

**Always prefer Turbo + Stimulus over custom JavaScript.** This project uses the Hotwire stack (Turbo Drive, Turbo Frames, Turbo Streams, Stimulus) as its primary frontend architecture. Direct `fetch()` calls, manual DOM manipulation, and standalone JS modules should only be used when Hotwire cannot handle the use case (e.g., map rendering with Leaflet/MapLibre).

### Decision Hierarchy

When adding frontend behavior, follow this order of preference:

1. **Turbo Drive** — Default. Links and forms work as SPAs with zero JS.
2. **Turbo Frames** — Partial page updates. Wrap a section in `<turbo-frame>` and target it from links/forms.
3. **Turbo Streams** — Server-pushed DOM updates. Use for CRUD operations that need to update multiple page sections. Respond with `turbo_stream` format from controllers.
4. **Stimulus controller** — Client-side behavior that Turbo can't handle (toggles, form validation, UI interactions). Keep controllers thin.
5. **Direct JS** — Last resort. Only for complex map interactions, canvas rendering, or third-party library integration (Leaflet, MapLibre, Chartkick).

### Turbo Stream Responses

For CRUD actions (create, update, destroy), respond with Turbo Streams instead of redirects or JSON:

```ruby
# Controller
def create
  @area = current_user.areas.new(area_params)
  if @area.save
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to areas_path }
    end
  end
end

# app/views/areas/create.turbo_stream.erb
<%= turbo_stream.prepend "areas-list", partial: "areas/area", locals: { area: @area } %>
<%= stream_flash(:notice, "Area created successfully") %>
```

Use the `FlashStreamable` concern (included in controllers) to send flash messages via Turbo Streams:

```ruby
include FlashStreamable

# In turbo_stream responses:
stream_flash(:notice, "Success message")
stream_flash(:error, "Error message")
```

### Flash Messages

- **Server-side (Turbo Stream):** Use `stream_flash` from the `FlashStreamable` concern. This appends a flash partial to the `#flash-messages` container.
- **Client-side (Stimulus/JS):** Import `Flash` from `flash_controller.js` and call `Flash.show(type, message)`:
  ```javascript
  import Flash from "./flash_controller"
  Flash.show("notice", "Operation completed")
  Flash.show("error", "Something went wrong")
  ```
- **Never** use raw `alert()`, `console.log` for user-facing messages, or create ad-hoc notification DOM elements.

### Stimulus Controllers

- Location: `app/javascript/controllers/`
- Naming: `<name>_controller.js` maps to `data-controller="<name>"` in HTML
- Use `static targets` for DOM references, `static values` for data from HTML attributes
- Always clean up in `disconnect()` (event listeners, timers, subscriptions)
- Prefer `data-action` attributes in HTML over `addEventListener` in JS
- For forms, prefer `this.formTarget.requestSubmit()` over manual `fetch()` calls — this preserves Turbo form handling, CSRF tokens, and Turbo Stream responses

### File Uploads

Use the unified `upload` controller (`upload_controller.js`) for all file upload forms. Configure via `data-upload-*-value` attributes:

```erb
<%= form_with data: {
  controller: "upload",
  upload_url_value: rails_direct_uploads_url,
  upload_field_name_value: "import[files][]",
  upload_multiple_value: true,
  upload_target: "form"
} do |f| %>
```

### What NOT to Do

- **No `fetch()` for form submissions** — Use `form_with` with Turbo. If you need custom headers (API key), use Stimulus to submit the form via `requestSubmit()`.
- **No `document.getElementById()` for updates** — Use Turbo Frames/Streams to replace DOM sections server-side.
- **No `showFlashMessage()` or ad-hoc flash functions** — Use `Flash.show()` (client) or `stream_flash` (server).
- **No ActionCable subscriptions for CRUD updates** — Use Turbo Stream broadcasts from models/controllers instead.
- **No separate upload controllers per form** — Use the unified `upload` controller with value attributes for configuration.

### When Direct JS Is Acceptable

- **Map rendering**: Leaflet (Maps v1) and MapLibre GL JS (Maps v2) require imperative JS for layers, markers, and interactions.
- **Chart rendering**: Chartkick handles its own DOM.
- **Third-party integrations**: Libraries that don't have Hotwire adapters.
- **Complex client-side computation**: Haversine distance, coordinate transforms, etc.

Even in these cases, wrap the integration in a Stimulus controller and connect it to the DOM via `data-controller`.

## Important Notes for Development

1. **Location Data**: Always handle location data with appropriate precision and privacy considerations
2. **PostGIS**: Leverage PostGIS features for geographic calculations rather than Ruby-based solutions
2.1 **Coordinates**: Use `lonlat` column in `points` table for geographic calculations
3. **Background Jobs**: Use Sidekiq for any potentially long-running operations
4. **Testing**: Include both unit and integration tests for location-based features
5. **Performance**: Consider database indexes for geographic queries
6. **Security**: Never log or expose user location data inappropriately
7. **Migrations**: Put all migrations (schema and data) in `db/migrate/`, not `db/data/`. Data manipulation migrations use the same `ActiveRecord::Migration` class and should run in the standard migration sequence.
8. **Public Sharing**: When implementing features that interact with stats, consider public sharing access patterns:
   - Use `public_accessible?` method to check if a stat can be publicly accessed
   - Support UUID-based access in API endpoints when appropriate
   - Respect expiration settings and disable sharing when expired
   - Only expose minimal necessary data in public sharing contexts

### Route Drawing Implementation (Critical)

⚠️ **IMPORTANT: Unit Mismatch in Route Splitting Logic**

Both Map v1 (Leaflet) and Map v2 (MapLibre) contain an **intentional unit mismatch** in route drawing that must be preserved for consistency:

**The Issue**:
- `haversineDistance()` function returns distance in **kilometers** (e.g., 0.5 km)
- Route splitting threshold is stored and compared as **meters** (e.g., 500)
- The code compares them directly: `0.5 > 500` = always **FALSE**

**Result**:
- The distance threshold (`meters_between_routes` setting) is **effectively disabled**
- Routes only split on **time gaps** (default: 60 minutes between points)
- This creates longer, more continuous routes that users expect

**Code Locations**:
- **Map v1**: `app/javascript/maps/polylines.js:390`
  - Uses `haversineDistance()` from `maps/helpers.js` (returns km)
  - Compares to `distanceThresholdMeters` variable (value in meters)

- **Map v2**: `app/javascript/maps_maplibre/layers/routes_layer.js:82-104`
  - Has built-in `haversineDistance()` method (returns km)
  - Intentionally skips `/1000` conversion to replicate v1 behavior
  - Comment explains this is matching v1's unit mismatch

**Critical Rules**:
1. ❌ **DO NOT "fix" the unit mismatch** - this would break user expectations
2. ✅ **Keep both versions synchronized** - they must behave identically
3. ✅ **Document any changes** - route drawing changes affect all users
4. ⚠️ If you ever fix this bug:
   - You MUST update both v1 and v2 simultaneously
   - You MUST migrate user settings (multiply existing values by 1000 or divide by 1000 depending on direction)
   - You MUST communicate the breaking change to users

**Additional Route Drawing Details**:
- **Time threshold**: 60 minutes (default) - actually functional
- **Distance threshold**: 500 meters (default) - currently non-functional due to unit bug
- **Sorting**: Map v2 sorts points by timestamp client-side; v1 relies on backend ASC order
- **API ordering**: Map v2 must request `order: 'asc'` to match v1's chronological data flow

## Contributing

- **Main Branch**: `master`
- **Development**: `dev` branch for pull requests
- **Issues**: GitHub Issues for bug reports
- **Discussions**: GitHub Discussions for feature requests
- **Community**: Discord server for questions

## Resources

- **Documentation**: https://dawarich.app/docs/
- **Repository**: https://github.com/Freika/dawarich
- **Discord**: https://discord.gg/pHsBjpt5J8
- **Changelog**: See CHANGELOG.md for version history
- **Development Setup**: See DEVELOPMENT.md
