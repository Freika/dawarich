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

## Deployment (1st time)

0. Set variables in Homelab repo
1. `make dokku_new_app`
2. `make dokku_setup_backups`
3. `make dokku_add_domain`
4. Create certificates files in Homelab repo
5. `make dokku_add_ssl`
6. Set SSL/TLS mode to Full in Cloudflare
7. `git remote add dokku dokku@DOKKU_SERVER_UP:APP_NAME`
8. `git push dokku master`
9. Add app.json to the repo:

```json
  {
    "scripts": {
      "predeploy": "dokku ps:stop wardu"
    },
    "formation": {
      "web": {
        "quantity": 1
      },
      "worker": {
        "quantity": 1
      }
    }
  }
```


{
  "cog": 271,
  "batt": 41,
  "lon": 2.29513,
  "acc": 5,
  "vel": 61,
  "vac": 21,
  "lat": 48.85833,
  "t": "u",
  "tst": 1497508651,
  "alt": 167,
  "_type": "location",
  "topic": "owntracks/jane/iphone",
  "p": 71,
  "tid": "JJ"
}

{"bs"=>1, # battery status
"p"=>102.818, # ping
"batt"=>100, # battery
"_type"=>"location", # type
"tid"=>"RO", # Tracker ID used to display the initials of a user (iOS,Android/string/optional) required for http mode
"topic"=>"owntracks/Frey/iPhone 12 Pro",
"alt"=>36,
"lon"=>13.504178,
"vel"=>0, # velocity
"t"=>"u",
"BSSID"=>"b0:f2:8:45:94:33",
"SSID"=>"FRITZ!Box 6660 Cable LQ",
"conn"=>"w", # connection, w = wifi, m = mobile, o = offline
"vac"=>3, # vertical accuracy
"acc"=>5, # horizontal accuracy
"tst"=>1702662679, Timestamp at which the beacon was seen (iOS/integer/epoch)
"lat"=>52.445526,
"m"=>1, # mode, significant = 1, move = 2
"inrids"=>["5f1d1b"], #  contains a list of region IDs the device is currently in (e.g. ["6da9cf","3defa7"]). Might be empty. (iOS,Android/list of strings/optional)
"inregions"=>["home"],
"point"=>{"bs"=>1,
"p"=>102.818,
"batt"=>100,
"_type"=>"location",
"tid"=>"RO",
"topic"=>"owntracks/Frey/iPhone 12 Pro",
"alt"=>36,
"lon"=>13.504178,
"vel"=>0,
"t"=>"u",
"BSSID"=>"b0:f2:8:45:94:33",
"SSID"=>"FRITZ!Box 6660 Cable LQ",
"conn"=>"w",
"vac"=>3,
"acc"=>5,
"tst"=>1702662679,
"lat"=>52.445526,
"m"=>1,
"inrids"=>["5f1d1b"],
"inregions"=>["home"]}}
18:51:18 web.1  | #<ActionController::Parameters {"bs"=>1,
"p"=>102.818,
"batt"=>100,
"_type"=>"location",
"tid"=>"RO",
"topic"=>"owntracks/Frey/iPhone 12 Pro",
"alt"=>36,
"lon"=>13.504178,
"vel"=>0,
"t"=>"u",
"BSSID"=>"b0:f2:8:45:94:33",
"SSID"=>"FRITZ!Box 6660 Cable LQ",
"conn"=>"w",
"vac"=>3,
"acc"=>5,
"tst"=>1702662679,
"lat"=>52.445526,
"m"=>1,
"inrids"=>["5f1d1b"],
"inregions"=>["home"],
"point"=>{"bs"=>1,
"p"=>102.818,
"batt"=>100,
"_type"=>"location",
"tid"=>"RO",
"topic"=>"owntracks/Frey/iPhone 12 Pro",
"alt"=>36,
"lon"=>13.504178,
"vel"=>0,
"t"=>"u",
"BSSID"=>"b0:f2:8:45:94:33",
"SSID"=>"FRITZ!Box 6660 Cable LQ",
"conn"=>"w",
"vac"=>3,
"acc"=>5,
"tst"=>1702662679,
"lat"=>52.445526,
"m"=>1,
"inrids"=>["5f1d1b"],
"inregions"=>["home"]}} permitted: false>
