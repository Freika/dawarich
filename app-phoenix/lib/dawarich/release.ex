defmodule Dawarich.Release do
  @moduledoc false
  @app :dawarich
  @ledger_schema "phoenix"
  @oban_schema "oban"

  def migrate, do: migrate([])

  def migrate(opts) do
    case Dawarich.Release.Lifecycle.mode(Keyword.get(opts, :env, System.get_env())) do
      {:ok, :rails} -> with_repos(&migrate_schemas(&1, opts), opts)
      {:ok, :native} -> with_repos(&Dawarich.Release.Native.migrate(&1, opts), opts)
      {:error, reason} -> raise Dawarich.CLI.Migrate.describe(reason)
    end
  end

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

  def check_runtime_apps! do
    check_runtime_apps!(Application.spec(@app, :applications) || [], &Application.load/1)
  end

  def check_runtime_apps!(root_apps, loader) when is_list(root_apps) and is_function(loader, 1) do
    Enum.reduce(root_apps, MapSet.new(), &check_runtime_app(&1, &2, loader, false))
    :ok
  end

  @doc false
  def ledger_schema, do: @ledger_schema

  defp with_repos(fun, opts \\ []) do
    map_repos(fun, opts)
    :ok
  end

  defp map_repos(fun, opts \\ []) do
    load_app()

    repos = if opts[:repo], do: [opts[:repo]], else: Application.fetch_env!(@app, :ecto_repos)

    for repo <- repos do
      {:ok, result, _} = Ecto.Migrator.with_repo(repo, fun)
      result
    end
  end

  defp migrate_schemas(repo, opts) do
    install_schemas(repo)
    copy_registration(repo, opts)
  end

  def install_schemas(repo) do
    ensure_schema(repo, @ledger_schema)

    Ecto.Migrator.run(repo, Application.app_dir(@app, "priv/repo/migrations"), :up,
      all: true,
      prefix: @ledger_schema,
      log: false
    )

    install_oban(repo)
  end

  defp copy_registration(repo, opts) do
    case Dawarich.ReleaseMigrations.V1_13_1.copy_registration_setting(repo, opts) do
      {:ok, _} -> :ok
      {:error, _} -> raise "registration copy refused"
    end
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

  defp check_runtime_app(app, seen, loader, optional?) do
    if MapSet.member?(seen, app) do
      seen
    else
      case loader.(app) do
        :ok ->
          check_runtime_app_spec(app, seen, loader)

        {:error, {:already_loaded, _}} ->
          check_runtime_app_spec(app, seen, loader)

        {:error, reason} ->
          if optional? and not_found_application?(reason) do
            seen
          else
            raise "failed to load runtime application #{app}: #{inspect(reason)}"
          end
      end
    end
  end

  defp check_runtime_app_spec(app, seen, loader) do
    case Application.spec(app) do
      nil ->
        raise "runtime application #{app} has no specification"

      spec ->
        Enum.each(Keyword.get(spec, :modules, []), fn module ->
          case Code.ensure_loaded(module) do
            {:module, ^module} -> :ok
            {:error, _} -> raise "runtime application #{app} is missing module #{inspect(module)}"
          end
        end)

        optional_apps = MapSet.new(Keyword.get(spec, :optional_applications, []))

        Enum.reduce(Keyword.get(spec, :applications, []), MapSet.put(seen, app), fn dependency,
                                                                                    acc ->
          check_runtime_app(dependency, acc, loader, MapSet.member?(optional_apps, dependency))
        end)
    end
  end

  defp not_found_application?({~c"no such file or directory", _}), do: true
  defp not_found_application?(_), do: false

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
