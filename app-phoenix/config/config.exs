import Config

config :elixir, :time_zone_database, Dawarich.Jobs.CronTimeZoneDatabase

config :dawarich, ecto_repos: [Dawarich.Repo]

config :dawarich, Dawarich.Repo,
  migration_source: "phoenix_schema_migrations",
  migration_default_prefix: "phoenix",
  prepare: :unnamed,
  parameters: [timezone: "UTC"],
  types: Dawarich.PostgrexTypes

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
config :phoenix, :filter_parameters, ["password", "api_key", "token", "secret"]

config :esbuild,
  version: "0.25.0",
  native: [
    args:
      ~w(js/app.js --bundle --format=esm --splitting --target=es2022 --outdir=../priv/static/native),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => Path.expand("../deps", __DIR__)
    }
  ]

import_config "#{config_env()}.exs"
