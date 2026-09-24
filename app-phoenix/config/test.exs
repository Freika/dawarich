import Config

config :dawarich, Dawarich.Repo,
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.get_env("DATABASE_USERNAME", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  database: System.get_env("PHOENIX_TEST_DATABASE", "dawarich_phoenix_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :dawarich, Oban, testing: :manual

config :logger, level: :warning
