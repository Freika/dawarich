
# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.2.1] — 2024-05-18

### Added

- Cities, visited by user and listed in right sidebar now also have an active link to a date they were visited

### Fixed

- Dark/light theme switcher in navbar is now being saved in user settings, so it persists between sessions

## [0.2.0] — 2024-05-05

*Breaking changes:*

This release changes how Dawarich handles a city visit threshold. Previously, the `MINIMUM_POINTS_IN_CITY` environment variable was used to determine the minimum *number of points* in a city to consider it as visited. Now, the `MIN_MINUTES_SPENT_IN_CITY` environment variable is used to determine the minimum *minutes* between two points to consider them as visited the same city.

The logic behind this is the following: if you have a lot of points in a city, it doesn't mean you've spent a lot of time there, especially if your OwnTracks app was in "Move" mode. So, it's better to consider the time spent in a city rather than the number of points.

In your docker-compose.yml file, you need to replace the `MINIMUM_POINTS_IN_CITY` environment variable with `MIN_MINUTES_SPENT_IN_CITY`. The default value is `60`, in minutes.

## [0.1.9] — 2024-04-25

### Added

- A test for CheckAppVersion service class

### Changed

- Replaced ActiveStorage with Shrine for file uploads

### Fixed

- `ActiveStorage::FileNotFoundError` error when uploading export files


## [0.1.8.1] — 2024-04-21

### Changed

- Set Redis as default cache store

### Fixed

- Consider timezone when parsing datetime params in points controller
- Add rescue for check version service class

## [0.1.8] — 2024-04-21

### Added

- Application version badge to the navbar with check for updates button
- Npm dependencies install to Github build workflow
- Footer

### Changed

- Disabled map points rendering by default to improve performance on big datasets

## [0.1.7] — 2024-04-17

### Added

- Map controls to toggle polylines and points visibility

### Changed

- Added content padding for mobile view
- Fixed stat card layout for mobile view

## [0.1.6.3] — 2024-04-07

### Changed

- Removed strong_params from POST /api/v1/points

## [0.1.6.1] — 2024-04-06

### Fixed

- `ActiveStorage::FileNotFoundError: ActiveStorage::FileNotFoundError` error when uploading export files

## [0.1.6] — 2024-04-06

You can now use [Overland](https://overland.p3k.app/) mobile app to track your location.

### Added

- Overland API endpoint (POST /api/v1/overland/batches)

### Changed

### Fixed

## [0.1.5] — 2024-04-05

You can now specify the host of the application by setting the `APPLICATION_HOST` environment variable in the `docker-compose.yml` file.

### Added

- Added version badge to navbar
- Added APPLICATION_HOST environment variable to docker-compose.yml to allow user to specify the host of the application
- Added CHANGELOG.md to keep track of changes

### Changed

- Specified gem version in Docker entrypoint

### Fixed
