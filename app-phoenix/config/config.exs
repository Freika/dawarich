import Config

config :dawarich, ecto_repos: [Dawarich.Repo]
config :dawarich, :reference_live, System.get_env("DAWARICH_REFERENCE_LIVE") == "1"

config :dawarich, Dawarich.Repo,
  migration_source: "phoenix_schema_migrations",
  migration_default_prefix: "phoenix",
  prepare: :unnamed,
  parameters: [timezone: "UTC"]

config :dawarich, Oban,
  repo: Dawarich.Repo,
  prefix: "oban",
  notifier: Oban.Notifiers.PG,
  peer: false,
  stager: false,
  queues: [],
  plugins: []

config :dawarich, DawarichWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  pubsub_server: Dawarich.PubSub,
  render_errors: [formats: [html: DawarichWeb.ErrorHTML], layout: false],
  check_origin: {DawarichWeb.Origin, :allowed?, []},
  live_view: [signing_salt: "dawarich live view"]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
