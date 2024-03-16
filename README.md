# Dawarich

This is a Rails app that receives location updates from Owntracks and stores them in a database. It also provides a web interface to view the location history.

## Features

### Google Maps Timeline import

You can import your Google Maps Timeline data into Wardu.

### Location history

You can view your location history on a map.

## How to start the app locally

0. Install and start Docker
1. `make build` to build docker image and install all the dependencies (up to 5-10 mins)
2. `make setup` to install gems, setup database and create test records
3. `make start` to start the app

Press `Ctrl+C` to stop the app.

Dockerized with https://betterprogramming.pub/rails-6-development-with-docker-55437314a1ad

## Deployment

`make build_and_push version=0.0.5` to build and push the docker image to the registry

Then go to Portainer and update the service to use the new image

