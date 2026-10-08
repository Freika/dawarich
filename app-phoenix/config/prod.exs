import Config

config :logger, level: :info

config :dawarich, DawarichWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
