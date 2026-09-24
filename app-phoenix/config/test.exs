import Config

connection = [
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.get_env("DATABASE_USERNAME", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres")
]

test_database = System.get_env("PHOENIX_TEST_DATABASE", "dawarich_phoenix_test")

config :dawarich,
       Dawarich.Repo,
       connection ++ [database: test_database, pool: Ecto.Adapters.SQL.Sandbox, pool_size: 5]

config :dawarich,
       Dawarich.ScratchRepo,
       connection ++
         [
           database: test_database <> "_scratch",
           pool_size: 5,
           timeout: :infinity,
           prepare: :unnamed,
           parameters: [timezone: "UTC"],
           migration_source: "phoenix_schema_migrations",
           migration_default_prefix: "phoenix"
         ]

config :dawarich, Oban, testing: :manual

config :logger, level: :warning
