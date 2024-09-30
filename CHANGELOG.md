
# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

# [0.14.5] - 2024-09-28

### Fixed

- GPX export now finishes correctly and does not throw an error in the end
- Deleting points from the Points page now preserves `start_at` and `end_at` values for the routes. #261
- Visits map now being rendered correctly in the Visits page. #262
- Fixed issue with timezones for negative UTC offsets. #194, #122
- Point page is no longer reloads losing provided timestamps when searching for points on Points page. #283

### Changed

- Map layers from Stadia were disabled for now due to necessary API key

# [0.14.4] - 2024-09-24

### Fixed

- GPX export now has time and elevation elements for each point

### Changed

- `GET /api/v1/points` will no longer return `raw_data` attribute for each point as it's a bit too much

### Added

- "Slim" version of `GET /api/v1/points`: pass optional param `?slim=true` to it and it will return only latitude, longitude and timestamp


# [0.14.3] — 2024-09-21

### Fixed

- Optimize order of the dockerfiles to leverage layer caching by @JoeyEamigh
- Add support for alternate postgres ports and db names in docker by @JoeyEamigh
- Creating exports directory if it doesn't exist by @tetebueno


## [0.14.1] — 2024-09-16

### Fixed

- Fixed a bug where the map was not loading due to invalid tile layer name


## [0.14.0] — 2024-09-15

### Added

- 17 new tile layers to choose from. Now you can select the tile layer that suits you the best. You can find the list of available tile layers in the map controls in the top right corner of the map under the layers icon.


## [0.13.7] — 2024-09-15

### Added

- `GET /api/v1/points` response now will include `X-Total-Pages` and `X-Current-Page` headers to make it easier to work with the endpoint
- The Pages point now shows total number of points found for provided date range

## Fixed

- Link to Visits page in notification informing about new visit suggestion


## [0.13.6] — 2024-09-13

### Fixed

- Flatten geodata retrieved from Immich before processing it to prevent errors


## [0.13.5] — 2024-09-08

### Added

- Links to view import points on the map and on the Points page on the Imports page.

### Fixed

- The Imports page now loading faster.

### Changed

- Default value for `RAILS_MAX_THREADS` was changed to 10.
- Visit suggestions background job was moved to its own low priority queue to prevent it from blocking other jobs.


## [0.13.4] — 2024-09-06

### Fixed

- Fixed a bug preventing the application from starting, when there is no users in the database but a data migration tries to update one.


## [0.13.3] — 2024-09-06

### Added

- Support for miles. To switch to miles, provide `DISTANCE_UNIT` environment variable with value `mi` in the `docker-compose.yml` file. Default value is `km`.

It's recommended to update your stats manually after changing the `DISTANCE_UNIT` environment variable. You can do this by clicking the "Update stats" button on the Stats page.

⚠️IMPORTANT⚠️: All settings are still should be provided in meters. All calculations though will be converted to feets and miles if `DISTANCE_UNIT` is set to `mi`.

```diff
  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    environment:
      APPLICATION_HOST: "localhost"
      APPLICATION_PROTOCOL: "http"
      APPLICATION_PORT: "3000"
      TIME_ZONE: "UTC"
+     DISTANCE_UNIT: "mi"
  dawarich_sidekiq:
    image: freikin/dawarich:latest
    container_name: dawarich_sidekiq
    environment:
      APPLICATION_HOST: "localhost"
      APPLICATION_PROTOCOL: "http"
      APPLICATION_PORT: "3000"
      TIME_ZONE: "UTC"
+     DISTANCE_UNIT: "mi"
```

### Changed

- Default time range on the map is now 1 day instead of 1 month. It will help you with performance issues if you have a lot of points in the database.


## [0.13.2] — 2024-09-06

### Fixed

- GeoJSON import now correctly imports files with FeatureCollection as a root object

### Changed

- The Points page now have number of points found for provided date range

## [0.13.1] — 2024-09-05

### Added

- `GET /api/v1/health` endpoint to check the health of the application with swagger docs

### Changed

- Ruby version updated to 3.3.4
- Visits suggestion process now will try to merge consecutive visits to the same place into one visit.


## [0.13.0] — 2024-09-03

The GPX and GeoJSON export release

⚠️ BREAKING CHANGES: ⚠️

Default exporting format is now GeoJSON instead of Owntracks-like JSON. This will allow you to use the exported data in other applications that support GeoJSON format. It's also important to highlight, that GeoJSON format does not describe a way to store any time-related data. Dawarich relies on the `timestamp` field in the GeoJSON format to determine the time of the point. The value of the `timestamp` field should be a Unix timestamp in seconds. If you import GeoJSON data that does not have a `timestamp` field, the point will not be imported.

Example of a valid point in GeoJSON format:

```json
{
  "type": "Feature",
  "geometry": {
    "type": "Point",
    "coordinates": [13.350110811262352, 52.51450815]
  },
  "properties": {
    "timestamp": 1725310036
  }
}
```

### Added

- GeoJSON format is now available for exporting data.
- GPX format is now available for exporting data.
- Importing GeoJSON is now available.

### Changed

- Default exporting format is now GeoJSON instead of Owntracks-like JSON. This will allow you to use the exported data in other applications that support GeoJSON format.

### Fixed

- Fixed a bug where the confirmation alert was shown more than once when deleting a point.


## [0.12.3] — 2024-09-02

### Added

- Resource limits to docke-compose.yml file to prevent server overload. Feel free to adjust the limits to your needs.

```yml
deploy:
  resources:
    limits:
      cpus: '0.50'    # Limit CPU usage to 50% of one core
      memory: '2G'    # Limit memory usage to 2GB
```

### Fixed

- Importing geodata from Immich will now not throw an error in the end of the process

### Changed

- A notification about an existing import with the same name will now show the import name
- Export file now also will contain `raw_dat` field for each point. This field contains the original data that was imported to the application.


## [0.12.2] — 2024-08-28

### Added

- `PATCH /api/v1/settings` endpoint to update user settings with swagger docs
- `GET /api/v1/settings` endpoint to get user settings with swagger docs
- Missing `page` and `per_page` query parameters to the `GET /api/v1/points` endpoint swagger docs

### Changed

- Map settings moved to the map itself and are available in the top right corner of the map under the gear icon.


## [0.12.1] — 2024-08-25

### Fixed

- Fixed a bug that prevented data migration from working correctly

## [0.12.0] — 2024-08-25

### The visit suggestion release

1. With this release deployment, data migration will work, starting visits suggestion process for all users.
2. After initial visit suggestion process, new suggestions will be calculated every 24 hours, based on points for last 24 hours.
3. If you have enabled reverse geocoding and (optionally) provided Photon Api Host, Dawarich will try to reverse geocode your visit and suggest specific places you might have visited, such as cafes, restaurants, parks, etc. If reverse geocoding is not enabled, or Photon Api Host is not provided, Dawarich will not try to suggest places but you'll be able to rename the visit yourself.
4. You can confirm or decline the visit suggestion. If you confirm the visit, it will be added to your timeline. If you decline the visit, it will be removed from your timeline. You'll be able to see all your confirmed, declined and suggested visits on the Visits page.


### Added

- A "Map" button to each visit on the Visits page to allow user to see the visit on the map
- Visits suggestion functionality. Read more on that in the release description
- Click on the visit name allows user to rename the visit
- Tabs to the Visits page to allow user to switch between confirmed, declined and suggested visits
- Places page to see and delete places suggested by Dawarich's visit suggestion process
- Importing a file will now trigger the visit suggestion process for the user

## [0.11.2] — 2024-08-22

### Changed

### Fixed

- Dawarich export was failing when attempted to be imported back to Dawarich.
- Imports page with a lot of imports should now load faster.


## [0.11.1] — 2024-08-21

### Changed

- `/api/v1/points` endpoint now returns 100 points by default. You can specify the number of points to return by passing the `per_page` query parameter. Example: `/api/v1/points?per_page=50` will return 50 points. Also, `page` query parameter is now available to paginate the results. Example: `/api/v1/points?per_page=50&page=2` will return the second page of 50 points.

## [0.11.0] — 2024-08-21

### Added

- A user can now trigger the import of their geodata from Immich to Dawarich by clicking the "Import Immich data" button in the Imports page.
- A user can now provide a url and an api key for their Immich instance and then trigger the import of their geodata from Immich to Dawarich. This can be done in the Settings page.

### Changed

- Table columns on the Exports page were reordered to make it more user-friendly.
- Exports are now being named with this pattern: "export_from_dd.mm.yyyy_to_dd.mm.yyyy.json" where "dd.mm.yyyy" is the date range of the export.
- Notification about any error now will include the stacktrace.

## [0.10.0] — 2024-08-20

### Added

- The `api/v1/stats` endpoint to get stats for the user with swagger docs

### Fixed

- Redis and DB containers are now being automatically restarted if they fail. Update your `docker-compose.yml` if necessary

```diff
  services:
  dawarich_redis:
    image: redis:7.0-alpine
    command: redis-server
    networks:
      - dawarich
    volumes:
      - shared_data:/var/shared/redis
+   restart: always
  dawarich_db:
    image: postgres:14.2-alpine
    container_name: dawarich_db
    volumes:
      - db_data:/var/lib/postgresql/data
      - shared_data:/var/shared
    networks:
      - dawarich
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
+   restart: always
```


See the [PR](https://github.com/Freika/dawarich/pull/185) or Swagger docs (`/api-docs`) for more information.

## [0.9.12] — 2024-08-15

### Fixed

- Owntracks points are now being saved to the database with the full attributes
- Existing owntracks points also filled with missing data
- Definition of "reverse geocoded points" is now correctly based on the number of points that have full reverse geocoding data instead of the number of points that have only country and city
- Fixed a bug in gpx importing scipt ([thanks, bluemax!](https://github.com/Freika/dawarich/pull/126))

## [0.9.11] — 2024-08-14

### Fixed

- A bug where an attempt to import a Google's Records.json file was failing due to wrong object being passed to a background worker

## [0.9.10] — 2024-08-14

### Added

- PHOTON_API_HOST env variable to set the host of the Photon API. It will allow you to use your own Photon API instance instead of the default one.

## [0.9.9] — 2024-07-30

### Added

- Pagination to exports page
- Pagination to imports page
- GET `/api/v1/points` endpoint to get all points for the user with swagger docs
- DELETE `/api/v1/points/:id` endpoint to delete a single point for the user with swagger docs
- DELETE `/api/v1/areas/:id` swagger docs
- User can now change route opacity in settings
- Points on the Points page can now be ordered by oldest or newest points
- Visits on the Visits page can now be ordered by oldest or newest visits

### Changed

- Point deletion is now being done using an api key instead of CSRF token

### Fixed

- OpenStreetMap layer is now being selected by default in map controls

---

## [0.9.8] — 2024-07-27

### Fixed

- Call to the background job to calculate visits

---

## [0.9.7] — 2024-07-27

### Fixed

- Name of background job to calculate visits

---

## [0.9.6] — 2024-07-27

### Fixed

- Map areas functionality

---

## [0.9.5] — 2024-07-27

### Added

- A possibility to create areas. To create an area, click on the Areas checkbox in map controls (top right corner of the map), then in the top left corner of the map, click on a small circle icon. This will enable draw tool, allowing you to draw an area. When you finish drawing, release the mouse button, and the area will be created. Click on the area, set the name and click "Save" to save the area. You can also delete the area by clicking on the trash icon in the area popup.
- A background job to calculate your visits. This job will calculate your visits based on the areas you've created.
- Visits page. This page will show you all your visits, calculated based on the areas you've created. You can see the date and time of the visit, the area you've visited, and the duration of the visit.
- A possibility to confirm or decline a visit. When you create an area, the visit is not calculated immediately. You need to confirm or decline the visit. You can do this on the Visits page. Click on the visit, then click on the "Confirm" or "Decline" button. If you confirm the visit, it will be added to your timeline. If you decline the visit, it will be removed from your timeline.
- Settings for visit calculation. You can set the minimum time spent in the area to consider it as a visit. This setting can be found in the Settings page.
- POST `/api/v1/areas` and GET `/api/v1/areas` endpoints. You can now create and list your areas via the API.

⚠️ Visits functionality is still in beta. If you find any issues, please let me know. ⚠️

### Fixed

- A route popup now correctly shows distance made in the route, not the distance between first and last points in the route.

---

## [0.9.4] — 2024-07-21

### Added

- A popup being shown when user clicks on a point now contains a link to delete the point. This is useful if you want to delete a point that was imported by mistake or you just want to clean up your data.

### Fixed

- Added `public/imports` and `public/exports` folders to git to prevent errors when exporting data

### Changed

- Some code from `maps_controller.js` was extracted into separate files

---


## [0.9.3] — 2024-07-19

### Added

- Admin flag to the database. Now not only the first user in the system can create new users, but also users with the admin flag set to true. This will make easier introduction of more admin functions in the future.

### Fixed

- Route hover distance is now being rendered in kilometers, not in meters, if route distance is more than 1 km.

---

## [0.9.2] — 2024-07-19

### Fixed

- Hover over a route does not move map anymore and shows the route tooltip where user hovers over the route, not at the end of the route. Click on route now will move the map to include the whole route.

---

## [0.9.1] — 2024-07-12

### Fixed

- Fixed a bug where total reverse geocoded points were calculated based on number of *imported* points that are reverse geocoded, not on the number of *total* reverse geocoded points.

---

## [0.9.0] — 2024-07-12

### Added

- Background jobs page. You can find it in Settings -> Background Jobs.
- Queue clearing buttons. You can clear all jobs in the queue.
- Reverse geocoding restart button. You can restart the reverse geocoding process for all of your points.
- Reverse geocoding continue button. Click on this button will start reverse geocoding process only for points that were not processed yet.
- A lot more data is now being saved in terms of reverse geocoding process. It will be used in the future to create more insights about your data.

### Changed

- Point reference to a user is no longer optional. It should not cause any problems, but if you see any issues, please let me know.
- ⚠️ Calculation of total reverse geocoded points was changed. ⚠️ Previously, the reverse geocoding process was recording only country and city for each point. Now, it records all the data that was received from the reverse geocoding service. This means that the total number of reverse geocoded points will be different from the previous one. It is recommended to restart the reverse geocoding process to get this data for all your existing points. Below you can find an example of what kind of data is being saved to your Dawarich database:

```json
{
  "place_id": 127850637,
  "licence": "Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright",
  "osm_type": "way",
  "osm_id": 718035022,
  "lat": "52.51450815",
  "lon": "13.350110811262352",
  "class": "historic",
  "type": "monument",
  "place_rank": 30,
  "importance": 0.4155071896625501,
  "addresstype": "historic",
  "name": "Victory Column",
  "display_name": "Victory Column, Großer Stern, Botschaftsviertel, Tiergarten, Mitte, Berlin, 10785, Germany",
  "address": {
    "historic": "Victory Column",
    "road": "Großer Stern",
    "neighbourhood": "Botschaftsviertel",
    "suburb": "Tiergarten",
    "borough": "Mitte",
    "city": "Berlin",
    "ISO3166-2-lvl4": "DE-BE",
    "postcode": "10785",
    "country": "Germany",
    "country_code": "de"
  },
  "boundingbox": [
    "52.5142449",
    "52.5147775",
    "13.3496725",
    "13.3505485"
  ]
}
```

---

## [0.8.7] — 2024-07-09

### Changed

- Added a logging config to the `docker-compose.yml` file to prevent logs from overflowing the disk. Now logs are being rotated and stored in the `log` folder in the root of the application. You can find usage example in the the repository's `docker-compose.yml` [file](https://github.com/Freika/dawarich/blob/master/docker-compose.yml#L50). Make sure to add this config to both `dawarich_app` and `dawarich_sidekiq` services.

```yaml
  logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
```

### Fixed

- Visiting notifications page now marks this notifications as read

---

## [0.8.6] — 2024-07-08

### Added

- Guide on how to setup a reverse proxy for Dawarich in the `docs/how_to_setup_reverse_proxy.md` file. This guide explains how to set up a reverse proxy for Dawarich using Nginx and Apache2.

### Removed

- `MAP_CENTER` env var from the `docker-compose.yml` file. This variable was used to set the default center of the map, but it is not needed anymore, as the map center is now hardcoded in the application. ⚠️ Feel free to remove this variable from your `docker-compose.yml` file. ⚠️

### Fixed

- Fixed a bug where Overland batch payload was not being processed due to missing coordinates in the payload. Now, if the coordinates are missing, the single point is skipped and the rest are being processed.

---

## [0.8.5] — 2024-07-08

### Fixed

- Set `'localhost'` string as a default value for `APPLICATION_HOSTS` environment variable in the `docker-compose.yml` file instead of an array. This is necessary to prevent errors when starting the application.

---

## [0.8.4] — 2024-07-08

### Added

- Support for multiple hosts. Now you can specify the host of the application by setting the `APPLICATION_HOSTS` (note plural form) environment variable in the `docker-compose.yml` file. Example:

```yaml
  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    environment:
      APPLICATION_HOSTS: "yourhost.com,www.yourhost.com,127.0.0.1"
```

Note, there should be no protocol prefixes in the `APPLICATION_HOSTS` variable, only the hostnames.

⚠️ It would also be better to migrate your current `APPLICATION_HOST` to `APPLICATION_HOSTS` to avoid any issues in the future, as `APPLICATION_HOST` will be deprecated in the nearest future. ⚠️

- Support for HTTPS. Now you can specify the protocol of the application by setting the `APPLICATION_PROTOCOL` environment variable in the `docker-compose.yml` file. Default value is `http` Example:

```yaml
  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    environment:
      APPLICATION_PROTOCOL: "https"
```

### Fixed

- Support for a `location-history.json` file from Google Takeout. It turned out, this file could contain not only an object with location data history, but also an array of objects with location data history. Now Dawarich can handle both cases and import the data correctly.


---

## [0.8.3] — 2024-07-03

### Added

- Notifications system. Now you will receive a notification when an import or export is finished, when stats update is completed and if any error occurs during any of these processes. Notifications are displayed in the top right corner of the screen and are stored in the database. You can see all your notifications on the Notifications page.
- Swagger API docs for `/api/v1/owntracks/points`. You can find the API docs at `/api-docs`.

---

## [0.8.2] — 2024-06-30

### Added

- Google Takeout geodata, taken from a [mobile devise](https://support.google.com/maps/thread/264641290/export-full-location-timeline-data-in-json-or-similar-format-in-the-new-version-of-timeline?hl=en), is now fully supported and can be imported to the Dawarich. The import process is the same as for other kinds of files, just select the JSON file and choose "Google Phone Takeout" as a source.

### Fixed

- Fixed a bug where an imported point was not being saved to the database if a point with the same timestamp and already existed in the database even if it was other user's point.

---

## [0.8.1] — 2024-06-30

### Added

- First user in the system can now create new users from the Settings page. This is useful for creating new users without the need to enable registrations. Default password for new users is `password`.

### Changed

- Registrations are now disabled by default. On the initial setup, a default user with email `user@domain.com` and password `password` is created. You can change the password in the Settings page.
- On the Imports page, now you can see the real number of points imported. Previously, this number might have not reflect the real number of points imported.

---

## [0.8.0] — 2024-06-25

### Added

- New Settings page to change Dawarich settings.
- New "Fog of War" toggle on the map controls.
- New "Fog of War meters" field in Settings. This field allows you to set the radius in meters around the point to be shown on the map. The map outside of this radius will be covered with a fog of war.

### Changed

- Order of points on Points page is now descending by timestamp instead of ascending.

---

## [0.7.1] — 2024-06-20

In new Settings page you can now change the following settings:

- Maximum distance between two points to consider them as one route
- Maximum time between two points to consider them as one route

### Added

- New Settings page to change Dawarich settings.

### Changed

- Settings link in user menu now redirects to the new Settings page.
- Old settings page is now available undeer Account link in user menu.

---

## [0.7.0] — 2024-06-19

## The GPX MVP Release

This release introduces support for GPX files to be imported. Now you can import GPX files from your devices to Dawarich. The import process is the same as for other kinds of files, just select the GPX file instead and choose "gpx" as a source. Both single-segmented and multi-segmented GPX files are supported.

⚠️ BREAKING CHANGES: ⚠️

- `/api/v1/points` endpoint is removed. Please use `/api/v1/owntracks/points` endpoint to upload your points from OwnTracks mobile app instead.

### Added

- Support for GPX files to be imported.

### Changed

- Couple of unnecessary params were hidden from route popup and now can be shown using `?debug=true` query parameter. This is useful for debugging purposes.

### Removed

- `/exports/download` endpoint is removed. Now you can download your exports directly from the Exports page.
- `/api/v1/points` endpoint is removed.

---

## [0.6.4] — 2024-06-18

### Added

- A link to Dawarich's website in the footer. It ain't much, but it's honest work.

### Fixed

- Fixed version badge in the navbar. Now it will show the correct version of the application.

### Changed

- Default map center location was changed.

---

## [0.6.3] — 2024-06-14

⚠️ IMPORTANT: ⚠️

Please update your `docker-compose.yml` file to include the following changes:

```diff
  dawarich_sidekiq:
    image: freikin/dawarich:latest
    container_name: dawarich_sidekiq
    volumes:
      - gem_cache:/usr/local/bundle/gems
+     - public:/var/app/public
```

### Added

- Added a line with public volume to sidekiq's docker-compose service to allow sidekiq process to write to the public folder

### Fixed

- Fixed a bug where the export file was not being created in the public folder

---

## [0.6.2] — 2024-06-14

This is a debugging release. No changes were made to the application.

---

## [0.6.0] — 2024-06-12

### Added

- Exports page to list existing exports download them or delete them

### Changed

- Exporting process now is done in the background, so user can close the browser tab and come back later to download the file. The status of the export can be checked on the Exports page.

ℹ️ Deleting Export file will only delete the file, not the points in the database. ℹ️

⚠️ BREAKING CHANGES: ⚠️

Volume, exposed to the host machine for placing files to import was changed. See the changes below.

Path for placing files to import was changed from `tmp/imports` to `public/imports`.

```diff
  ...

  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    volumes:
      - gem_cache:/usr/local/bundle/gems
-     - tmp:/var/app/tmp
+     - public:/var/app/public/imports

  ...
```

```diff
  ...

volumes:
  db_data:
  gem_cache:
  shared_data:
- tmp:
+ public:
```

---

## [0.5.3] — 2024-06-10

### Added

- A data migration to remove points with 0.0, 0.0 coordinates. This is necessary to prevent errors when calculating distance in Stats page.

### Fixed

- Reworked code responsible for importing "Records.json" file from Google Takeout. Now it is more reliable and faster, and should not throw as many errors as before.

---

## [0.5.2] — 2024-06-08

### Added

- Test version of google takeout importing service for exports from users' phones

---

## [0.5.1] — 2024-06-07

### Added

- Background jobs concurrency now can be set with `BACKGROUND_PROCESSING_CONCURRENCY` env variable in `docker-compose.yml` file. Default value is 10.
- Hand-made favicon

### Changed

- Change minutes to days and hours on route popup

### Fixed

- Improved speed of "Stats" page loading by removing unnecessary queries

---

## [0.5.0] — 2024-05-31

### Added

- New buttons to quickly move to today's, yesterday's and 7 days data on the map
- "Download JSON" button to points page
- For debugging purposes, now user can use `?meters_between_routes=500` and `?minutes_between_routes=60` query parameters to set the distance and time between routes to split them on the map. This is useful to understand why routes might not be connected on the map.
- Added scale indicator to the map

### Changed

- Removed "Your data" page as its function was replaced by "Download JSON" button on the points page
- Hovering over a route now also shows time and distance to next route as well as time and distance to previous route. This allows user to understand why routes might not be connected on the map.

---

## [0.4.3] — 2024-05-30

### Added

- Now user can hover on a route and see when it started, when it ended and how much time it took to travel

### Fixed

- Timestamps in export form are now correctly assigned from the first and last points tracked by the user
- Routes are now being split based both on distance and time. If the time between two consecutive points is more than 60 minutes, the route is split into two separate routes. This improves visibility of the routes on the map.

---

## [0.4.2] — 2024-05-29

### Changed

- Routes are now being split into separate one. If distance between two consecutive points is more than 500 meters, the route is split into two separate routes. This improves visibility of the routes on the map.
- Background jobs concurrency is increased from 5 to 10 to speed up the processing of the points.

### Fixed

- Point data, accepted from OwnTracks and Overland, is now being checked for duplicates. If a point with the same timestamp and coordinates already exists in the database, it will not be saved.

---
## [0.4.1] — 2024-05-25

### Added

- Heatmap layer on the map to show the density of points

---

## [0.4.0] — 2024-05-25

**BREAKING CHANGES**:

- `/api/v1/points` is still working, but will be **deprecated** in nearest future. Please use `/api/v1/owntracks/points` instead.
- All existing points recorded directly to the database via Owntracks or Overland will be attached to the user with id 1.

### Added

- Each user now have an api key, which is required to make requests to the API. You can find your api key in your profile settings.
- You can re-generate your api key in your profile settings.
- In your user profile settings you can now see the instructions on how to use the API with your api key for both OwnTracks and Overland.
- Added docs on how to use the API with your api key. Refer to `/api-docs` for more information.
- `POST /api/v1/owntracks/points` endpoint.
- Points are now being attached to a user directly, so you can only see your own points and no other users of your applications can see your points.

### Changed

- `/api/v1/overland/batches` endpoint now requires an api key to be passed in the url. You can find your api key in your profile settings.
- All existing points recorded directly to the database will be attached to the user with id 1.
- All stats and maps are now being calculated and rendered based on the user's points only.
- Default `TIME_ZONE` environment variable is now set to 'UTC' in the `docker-compose.yml` file.

### Fixed

- Fixed a bug where marker on the map was rendering timestamp without considering the timezone.

---

## [0.3.2] — 2024-05-23

### Added

- Docker volume for importing Google Takeout data to the application

### Changed

- Instruction on how to import Google Takeout data to the application

---

## [0.3.1] — 2024-05-23

### Added

- Instruction on how to import Google Takeout data to the application

---

## [0.3.0] — 2024-05-23

### Added

- Add Points page to display all the points as a table with pagination to allow users to delete points
- Sidekiq web interface to monitor background jobs is now available at `/sidekiq`
- Now you can choose a date range of points to be exported

---

## [0.2.6] — 2024-05-23

### Fixed

- Stop selecting `raw_data` column during requests to `imports` and `points` tables to improve performance.

### Changed

- Rename PointsController to MapController along with all the views and routes

### Added

- Add Points page to display all the points as a table with pagination to allow users to delete points

---

## [0.2.5] — 2024-05-21

### Fixed

- Stop ignoring `raw_data` column during requests to `imports` and `points` tables. This was preventing points from being created.

---

## [0.2.4] — 2024-05-19

### Added

- In right sidebar you can now see the total amount of geopoints aside of kilometers traveled

### Fixed

- Improved overall performance if the application by ignoring `raw_data` column during requests to `imports` and `points` tables.

---


## [0.2.3] — 2024-05-18

### Added

- Now you can import `records.json` file from your Google Takeout archive, not just Semantic History Location JSON files. The import process is the same as for Semantic History Location JSON files, just select the `records.json` file instead and choose "google_records" as a source.

---


## [0.2.2] — 2024-05-18

### Added

- Swagger docs, can be found at `https:<your-host>/api-docs`

---

## [0.2.1] — 2024-05-18

### Added

- Cities, visited by user and listed in right sidebar now also have an active link to a date they were visited

### Fixed

- Dark/light theme switcher in navbar is now being saved in user settings, so it persists between sessions

---

## [0.2.0] — 2024-05-05

*Breaking changes:*

This release changes how Dawarich handles a city visit threshold. Previously, the `MINIMUM_POINTS_IN_CITY` environment variable was used to determine the minimum *number of points* in a city to consider it as visited. Now, the `MIN_MINUTES_SPENT_IN_CITY` environment variable is used to determine the minimum *minutes* between two points to consider them as visited the same city.

The logic behind this is the following: if you have a lot of points in a city, it doesn't mean you've spent a lot of time there, especially if your OwnTracks app was in "Move" mode. So, it's better to consider the time spent in a city rather than the number of points.

In your docker-compose.yml file, you need to replace the `MINIMUM_POINTS_IN_CITY` environment variable with `MIN_MINUTES_SPENT_IN_CITY`. The default value is `60`, in minutes.

---

## [0.1.9] — 2024-04-25

### Added

- A test for CheckAppVersion service class

### Changed

- Replaced ActiveStorage with Shrine for file uploads

### Fixed

- `ActiveStorage::FileNotFoundError` error when uploading export files

---

## [0.1.8.1] — 2024-04-21

### Changed

- Set Redis as default cache store

### Fixed

- Consider timezone when parsing datetime params in points controller
- Add rescue for check version service class

---

## [0.1.8] — 2024-04-21

### Added

- Application version badge to the navbar with check for updates button
- Npm dependencies install to Github build workflow
- Footer

### Changed

- Disabled map points rendering by default to improve performance on big datasets

---

## [0.1.7] — 2024-04-17

### Added

- Map controls to toggle polylines and points visibility

### Changed

- Added content padding for mobile view
- Fixed stat card layout for mobile view

---

## [0.1.6.3] — 2024-04-07

### Changed

- Removed strong_params from POST /api/v1/points

---

## [0.1.6.1] — 2024-04-06

### Fixed

- `ActiveStorage::FileNotFoundError: ActiveStorage::FileNotFoundError` error when uploading export files

---

## [0.1.6] — 2024-04-06

You can now use [Overland](https://overland.p3k.app/) mobile app to track your location.

### Added

- Overland API endpoint (POST /api/v1/overland/batches)

### Changed

### Fixed

---

## [0.1.5] — 2024-04-05

You can now specify the host of the application by setting the `APPLICATION_HOST` environment variable in the `docker-compose.yml` file.

### Added

- Added version badge to navbar
- Added APPLICATION_HOST environment variable to docker-compose.yml to allow user to specify the host of the application
- Added CHANGELOG.md to keep track of changes

### Changed

- Specified gem version in Docker entrypoint

### Fixed
