# Dawarich

[Discord](https://discord.gg/pHsBjpt5J8) | [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/H2H3IDYDD)

Dawarich is a self-hosted web application to replace Google Timeline (aka Google Location History). It allows you to import your location history from Google Maps Timeline and Owntracks, view it on a map and see some statistics, such as the number of countries and cities visited, and distance traveled.

You can find changelog [here](CHANGELOG.md).

## Usage



To track your location, install the [Owntracks app](https://owntracks.org/booklet/guide/apps/) or [Overland app](https://overland.p3k.app/) on your phone and configure it to send location updates to your Dawarich instance.

Currently, the app only supports [HTTP mode](https://owntracks.org/booklet/tech/http/).

### OwnTracks

The url to send the location updates to is `http://<your-dawarich-instance>/api/v1/owntracks/points?api_key=YOUR_API_KEY`.

### Overland

The url to send the location updates to is `http://<your-dawarich-instance>/api/v1/overland/batches?api_key=YOUR_API_KEY`.

Your API key can be found and/or generated in the user settings.

To import your Google Maps Timeline data, download your location history from [Google Takeout](https://takeout.google.com/) and upload it to Dawarich.

## How-to's

- [How to import Google Takeout to Dawarich](https://github.com/Freika/dawarich/wiki/How-to-import-your-Google-Takeout-data)
- [How to Import Google Semantic History to Dawarich](https://github.com/Freika/dawarich/wiki/How-to-import-your-Google-Semantic-History-data)

## Features

### Location Tracking

You can track your location using the Owntracks or Overland app.

### Location history

You can view your location history on a map. On the map you can enable/disable the following layers:

- Heatmap
- Points
- Lines between points

### Statistics

You can see the number of countries and cities visited, the distance traveled, and the time spent in each country, splitted by years and months.

### Import

You can import your Google Maps Timeline data into Dawarich as well as Owntracks data.

## How to start the app locally

`docker-compose up` to start the app. The app will be available at `http://localhost:3000`.

Press `Ctrl+C` to stop the app.

## How to deploy the app

Copy the contents of the `docker-compose.yml` file to your server and run `docker-compose up`.

## Environment variables

```
MIN_MINUTES_SPENT_IN_CITY — minimum minutes between two points to consider them as visited the same city, e.g. `60`
MAP_CENTER — default map center, e.g. `55.7558,37.6176`
TIME_ZONE — time zone, e.g. `Europe/Berlin`
APPLICATION_HOST — host of the application, e.g. `localhost` or `dawarich.example.com`
```

## Screenshots

![Map](screenshots/map.jpeg)

![Stats](screenshots/stats.jpeg)

![Import](screenshots/imports.jpeg)

## Star History

As you could probably guess, I like statistics.

<a href="https://star-history.com/#Freika/dawarich&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Freika/dawarich&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Freika/dawarich&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Freika/dawarich&type=Date" />
 </picture>
</a>
