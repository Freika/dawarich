ExUnit.start()
Application.put_env(:dawarich, :allowed_hosts, [])
Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

scratch_repos = [Dawarich.ScratchRepo, Dawarich.ScratchCaseRepo]

for repo <- scratch_repos do
  scratch = repo.config()

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
end
