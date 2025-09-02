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
- **Stat**: Calculated statistics and metrics

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

## API Documentation

- **Framework**: rSwag (Swagger/OpenAPI)
- **Location**: `/api-docs` endpoint
- **Authentication**: JWT-based for API access

## Database Schema

### Key Tables
- `users` - User accounts and settings
- `points` - Location points with PostGIS geometry
- `tracks` - Route collections
- `areas` - User-defined geographic areas
- `visits` - Detected area visits
- `trips` - Travel periods
- `imports`/`exports` - Data transfer operations
- `stats` - Calculated metrics

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
- **Linting**: RuboCop with Rails extensions
- **Security**: Brakeman, bundler-audit
- **Dependencies**: Strong Migrations for safe database changes
- **Performance**: Stackprof for profiling

### Commands
```bash
bundle exec rubocop                  # Code linting
bundle exec brakeman                 # Security scan
bundle exec bundle-audit             # Dependency security
```

## Important Notes for Development

1. **Location Data**: Always handle location data with appropriate precision and privacy considerations
2. **PostGIS**: Leverage PostGIS features for geographic calculations rather than Ruby-based solutions
2.1 **Coordinates**: Use `lonlat` column in `points` table for geographic calculations
3. **Background Jobs**: Use Sidekiq for any potentially long-running operations
4. **Testing**: Include both unit and integration tests for location-based features
5. **Performance**: Consider database indexes for geographic queries
6. **Security**: Never log or expose user location data inappropriately

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
