# SoloCustomerTemplate

This is a Rails 7.0.2.3 app template with test suite, user auth and development docker env.

## How to rename the app

Run

```bash
ruby rename_app.rb old_app_name new_app_name
```

Notice, the name must be in snake_case. Default app name is `solo_customer_template`.


## How to start the app locally

0. Install and start Docker
1. `make build` to build docker image and install all the dependencies (up to 5-10 mins)
2. `make setup` to install gems, setup database and create test records
3. `make start` to start the app

Press `Ctrl+C` to stop the app.

Dockerized with https://betterprogramming.pub/rails-6-development-with-docker-55437314a1ad
