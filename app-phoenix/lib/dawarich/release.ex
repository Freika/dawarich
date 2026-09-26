defmodule Dawarich.Release do
  @moduledoc false
  @app :dawarich
  @ledger_schema "phoenix"
  @oban_schema "oban"

  def migrate, do: with_repos(&migrate_schemas/1)

  def migrate_oban, do: with_repos(&install_oban/1)

  def readiness do
    if Enum.all?(map_repos(&schemas_ready?/1)), do: :ready, else: :schemas_behind
  rescue
    DBConnection.ConnectionError -> :no_connection
  end

  def halt_unless_ready do
    case readiness() do
      :ready -> :ok
      :schemas_behind -> System.halt(3)
      :no_connection -> System.halt(5)
    end
  end

  @doc false
  def ledger_schema, do: @ledger_schema

  defp with_repos(fun) do
    map_repos(fun)
    :ok
  end

  defp map_repos(fun) do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, result, _} = Ecto.Migrator.with_repo(repo, fun)
      result
    end
  end

  defp migrate_schemas(repo) do
    ensure_schema(repo, @ledger_schema)
    Ecto.Migrator.run(repo, :up, all: true, prefix: @ledger_schema, log: false)
    install_oban(repo)
  end

  defp install_oban(repo) do
    ensure_schema(repo, @oban_schema)

    Ecto.Migrator.run(repo, oban_migrations_path(), :up,
      all: true,
      prefix: @oban_schema,
      log: false
    )
  end

  defp ensure_schema(repo, schema) do
    %{rows: [[exists]]} =
      repo.query!("SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = $1)", [schema],
        log: false
      )

    exists || repo.query!("CREATE SCHEMA IF NOT EXISTS #{schema}", [], log: false)
  end

  defp schemas_ready?(repo) do
    [
      {Ecto.Migrator.migrations_path(repo), @ledger_schema},
      {oban_migrations_path(), @oban_schema}
    ]
    |> Enum.all?(fn {path, prefix} ->
      repo
      |> Ecto.Migrator.migrations(path,
        prefix: prefix,
        skip_table_creation: true,
        migration_lock: false
      )
      |> Enum.all?(&match?({:up, _, _}, &1))
    end)
  rescue
    Postgrex.Error -> false
  end

  defp oban_migrations_path do
    Application.app_dir(@app, "priv/repo/oban_migrations")
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
