release: bundle exec rails db:migrate && bundle exec rake achievements:backfill
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
