defmodule Dawarich.Release do
  @moduledoc false
  @app :dawarich
  @ledger_schema "phoenix"
  @oban_schema "oban"

  def migrate, do: with_repos(&migrate_schemas/1)

  def migrate_oban, do: with_repos(&install_oban/1)

  @doc false
  def ledger_schema, do: @ledger_schema

  defp with_repos(fun) do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fun)
    end

    :ok
  end

  defp migrate_schemas(repo) do
    repo.query!("CREATE SCHEMA IF NOT EXISTS #{@ledger_schema}", [], log: false)
    Ecto.Migrator.run(repo, :up, all: true, prefix: @ledger_schema, log: false)
    install_oban(repo)
  end

  defp install_oban(repo) do
    repo.query!("CREATE SCHEMA IF NOT EXISTS #{@oban_schema}", [], log: false)

    Ecto.Migrator.run(repo, oban_migrations_path(), :up,
      all: true,
      prefix: @oban_schema,
      log: false
    )
  end

  defp oban_migrations_path do
    Application.app_dir(@app, "priv/repo/oban_migrations")
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
