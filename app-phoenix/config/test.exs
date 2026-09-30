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

scratch =
  connection ++
    [
      pool_size: 5,
      timeout: :infinity,
      prepare: :unnamed,
      parameters: [timezone: "UTC"],
      migration_source: "phoenix_schema_migrations",
      migration_default_prefix: "phoenix"
    ]

config :dawarich, Dawarich.ScratchRepo, [database: test_database <> "_scratch"] ++ scratch

config :dawarich,
       Dawarich.ScratchCaseRepo,
       [database: test_database <> "_scratch_case"] ++ scratch

config :dawarich, Oban, testing: :manual

config :dawarich, :redis,
  url: System.get_env("PHOENIX_TEST_REDIS_URL", "redis://127.0.0.1:7153"),
  database: 1

config :dawarich, :jobs_runtime, false
config :dawarich, :jobs_repo, Dawarich.ScratchRepo
config :dawarich, :app_version_file, Path.expand("../../.app_version", __DIR__)
config :dawarich, :rails_root, Path.expand("../..", __DIR__)
config :dawarich, :mail_transport, Dawarich.Mail.TestTransport

config :dawarich, DawarichWeb.Endpoint,
  secret_key_base: String.duplicate("phoenix-a2-test-endpoint-secret-", 3)

config :logger, level: :warning

config :dawarich, :rails_secret, "phoenix-a2-cookie-fixture-secret-not-for-production"

config :dawarich, :i18n_path, Path.expand("../tmp/i18n.json", __DIR__)
config :dawarich, :achievements_path, Path.expand("../tmp/achievements.json", __DIR__)
