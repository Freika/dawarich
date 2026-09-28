ExUnit.start()
Application.put_env(:dawarich, :allowed_hosts, [])
Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

scratch = Dawarich.ScratchRepo.config()

case Dawarich.ScratchRepo.__adapter__().storage_up(scratch) do
  :ok -> :ok
  {:error, :already_up} -> :ok
end

{:ok, _} = Dawarich.ScratchRepo.start_link()

Dawarich.ScratchRepo.query!(
  ~s(ALTER DATABASE "#{scratch[:database]}" SET timezone TO 'Pacific/Chatham'),
  [],
  log: false
)

:ok = Dawarich.ScratchRepo.stop()
{:ok, _} = Dawarich.ScratchRepo.start_link()
Dawarich.ScratchRepo.query!("CREATE SCHEMA IF NOT EXISTS phoenix", [], log: false)

Ecto.Migrator.run(
  Dawarich.ScratchRepo,
  Ecto.Migrator.migrations_path(Dawarich.Repo),
  :up,
  all: true,
  prefix: "phoenix",
  log: false
)

Dawarich.ScratchRepo.query!("CREATE SCHEMA IF NOT EXISTS oban", [], log: false)

Ecto.Migrator.run(
  Dawarich.ScratchRepo,
  Path.expand("../priv/repo/oban_migrations", __DIR__),
  :up,
  all: true,
  prefix: "oban",
  log: false
)

Dawarich.MigrationModules.purge()
