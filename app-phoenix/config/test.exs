import Config

config :sentry, dsn: nil, enable_logs: false

connection = [
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  username: System.get_env("DATABASE_USERNAME", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres")
]

partition = System.get_env("MIX_TEST_PARTITION", "")

if partition != "" and partition not in ~w(1 2 3 4),
  do: raise("MIX_TEST_PARTITION must be between 1 and 4")

test_database = System.get_env("PHOENIX_TEST_DATABASE", "dawarich_phoenix_test") <> partition
redis_url = System.get_env("PHOENIX_TEST_REDIS_URL", "redis://127.0.0.1:7153")

redis_url =
  if partition == "" do
    redis_url
  else
    uri = URI.parse(redis_url)
    URI.to_string(%{uri | port: (uri.port || 6379) + String.to_integer(partition) - 1})
  end

test_root =
  if partition == "",
    do: Path.expand("../tmp", __DIR__),
    else: Path.expand("../tmp/partitions/#{partition}", __DIR__)

config :dawarich, :test_tmp_dir, Path.join(test_root, "system")

config :dawarich,
       Dawarich.Repo,
       connection ++
         [
           database: test_database,
           pool: Ecto.Adapters.SQL.Sandbox,
           pool_size: max(5, System.schedulers_online() * 2)
         ]

scratch =
  connection ++
    [
      pool_size: 5,
      timeout: :infinity,
      prepare: :unnamed,
      parameters: [timezone: "UTC"],
      types: Dawarich.PostgrexTypes,
      migration_source: "phoenix_schema_migrations",
      migration_default_prefix: "phoenix"
    ]

config :dawarich, Dawarich.ScratchRepo, [database: test_database <> "_scratch"] ++ scratch

config :dawarich,
       Dawarich.ScratchCaseRepo,
       [database: test_database <> "_scratch_case"] ++ scratch

config :dawarich,
       Dawarich.TracksScratchRepo,
       [database: test_database <> "_scratch_tracks"] ++ scratch

config :dawarich, Oban, testing: :manual

config :dawarich, :redis,
  url: redis_url,
  database: 1,
  cache_database: 0

config :dawarich, :front_runtime, false
config :dawarich, :jobs_runtime, false
config :dawarich, :jobs_repo, Dawarich.ScratchRepo
config :dawarich, :geocoding_http, Dawarich.Geocoding.FakeHttp
config :dawarich, :extraction_timeout_ms, 600_000
config :dawarich, :app_version_file, Path.expand("../../.app_version", __DIR__)
config :dawarich, :rails_root, Path.expand("../..", __DIR__)
config :dawarich, :mail_transport, Dawarich.Mail.TestTransport

config :dawarich, DawarichWeb.Endpoint,
  secret_key_base: String.duplicate("phoenix-a2-test-endpoint-secret-", 3)

config :logger, level: :warning

config :dawarich, :rails_secret, "phoenix-a2-cookie-fixture-secret-not-for-production"

config :dawarich, :i18n_path, Path.join(test_root, "i18n.json")
config :dawarich, :achievements_path, Path.join(test_root, "achievements.json")

config :dawarich, :cable, bus: false

config :dawarich,
       :cable_prefix,
       if(partition == "", do: "dawarich_a12a", else: "dawarich_a12a_part#{partition}")

config :dawarich, :cloud_test_loopback, true
