# Dawarich

This is a Rails app that receives location updates from Owntracks and stores them in a database. It also provides a web interface to view the location history.

## Usage

To track your location, install the Owntracks [app](https://owntracks.org/booklet/guide/apps/) on your phone and configure it to send location updates to your Dawarich instance. Currently, the app only supports HTTP mode. The url to send the location updates to is `http://<your-dawarich-instance>/api/v1/points`.

To import your Google Maps Timeline data, download your location history from [Google Takeout](https://takeout.google.com/) and upload it to Dawarich.

## Features

### Import

You can import your Google Maps Timeline data into Dawarich as well as Owntracks data.

### Location history

You can view your location history on a map.

## How to start the app locally

`docker-compose up` to start the app. The app will be available at `http://localhost:3000`.

Press `Ctrl+C` to stop the app.

## How to deploy the app

Copy the contents of the `docker-compose.yml` file to your server and run `docker-compose up`.

## Environment variables

`MINIMUM_POINTS_IN_CITY` — minimum number of points in a city to consider it as a city visited, eg. `10`

`MAP_CENTER` — default map center, e.g. `55.7558,37.6176`

`TIME_ZONE` — time zone, e.g. `Europe/Berlin`
