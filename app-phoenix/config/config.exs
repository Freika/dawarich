import Config

config :dawarich, ecto_repos: [Dawarich.Repo]

config :dawarich, Dawarich.Repo,
  migration_source: "phoenix_schema_migrations",
  migration_default_prefix: "phoenix",
  prepare: :unnamed

config :dawarich, Oban,
  repo: Dawarich.Repo,
  prefix: "oban",
  notifier: Oban.Notifiers.PG,
  peer: false,
  stager: false,
  queues: [],
  plugins: []

import_config "#{config_env()}.exs"
