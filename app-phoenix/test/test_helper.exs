ExUnit.start(exclude: [:rails_parity])

if System.get_env("MIX_TEST_PARTITION", "") != "" do
  tmp = Application.fetch_env!(:dawarich, :test_tmp_dir)
  File.mkdir_p!(tmp)
  System.put_env("TMPDIR", tmp)
  System.put_env("PHOENIX_TEST_REDIS_URL", Application.fetch_env!(:dawarich, :redis)[:url])
end

Application.put_env(:dawarich, :allowed_hosts, [])
Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :auto)
Dawarich.PublicBaseline.ensure_current!(Dawarich.Repo)

Dawarich.Repo.query!("CREATE SCHEMA IF NOT EXISTS phoenix", [], log: false)

Ecto.Migrator.run(
  Dawarich.Repo,
  Ecto.Migrator.migrations_path(Dawarich.Repo),
  :up,
  all: true,
  prefix: "phoenix",
  log: false
)

Dawarich.MigrationModules.purge()
Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

scratch_repos = [Dawarich.ScratchRepo, Dawarich.ScratchCaseRepo, Dawarich.TracksScratchRepo]

for repo <- scratch_repos do
  scratch = repo.config()

  if byte_size(scratch[:database]) > 63,
    do: raise("#{scratch[:database]} exceeds Postgres' 63-byte identifier limit")

  case repo.__adapter__().storage_up(scratch) do
    :ok -> :ok
    {:error, :already_up} -> :ok
  end

  {:ok, _} = repo.start_link()

  repo.query!(
    ~s(ALTER DATABASE "#{scratch[:database]}" SET timezone TO 'Pacific/Chatham'),
    [],
    log: false
  )

  :ok = repo.stop()
end

{:ok, _} =
  Supervisor.start_link(scratch_repos,
    strategy: :one_for_one,
    name: Dawarich.ScratchSupervisor
  )

for repo <- scratch_repos do
  repo.query!("CREATE SCHEMA IF NOT EXISTS phoenix", [], log: false)

  Ecto.Migrator.run(
    repo,
    Ecto.Migrator.migrations_path(Dawarich.Repo),
    :up,
    all: true,
    prefix: "phoenix",
    log: false
  )

  repo.query!("CREATE SCHEMA IF NOT EXISTS oban", [], log: false)

  Ecto.Migrator.run(
    repo,
    Path.expand("../priv/repo/oban_migrations", __DIR__),
    :up,
    all: true,
    prefix: "oban",
    log: false
  )

  Dawarich.MigrationModules.purge()
  Dawarich.PublicBaseline.ensure_current!(repo)
end

Dawarich.LaneGuard.attach!()
