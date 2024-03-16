# Setting up the project
build:
	docker-compose build --no-cache

setup_backend: bundle

setup:
	make bundle
	make setup_frontend
	make setup_db

bundle:
	docker-compose run --rm dawarich_app gem install bundler --conservative
	docker-compose run --rm dawarich_app bundle install

setup_frontend:
	npm i daisyui

setup_db:
	docker-compose run --rm dawarich_app rails db:create db:migrate db:seed

migrate:
	docker-compose run --rm dawarich_app bin/rails db:migrate
rollback:
	docker-compose run --rm dawarich_app bin/rails db:rollback
# Setting up the project


# Debugging the project
bash:
	docker-compose run --rm dawarich_app sh

console:
	docker-compose run --rm dawarich_app bundle exec rails c

debug:
	docker attach dawarich_app
# Debugging the project


# Running the project
start_sidekiq:
	docker-compose up sidekiq

start:
	docker-compose up -d dawarich_app
	make debug

overmind:
	overmind start -f Procfile.dev
# Running the project

test:
	RAILS_ENV=test NODE_ENV=test docker-compose run --rm dawarich_test bundle exec rspec
# Running tests

deploy:
	git push dokku master

unlock_deploy:
	ssh dokku_frey 'dokku apps:unlock dawarich'

tail_production_log:
	ssh dokku_frey 'dokku logs dawarich --tail'

production_migrate:
	ssh dokku_frey 'dokku run dawarich bundle exec rails db:migrate'

build_and_push:
	docker build . -t dawarich:$(version) --platform=linux/amd64
	docker tag dawarich:$(version) registry.chibi.rodeo/dawarich:$(version)
	docker push registry.chibi.rodeo/dawarich:$(version)
