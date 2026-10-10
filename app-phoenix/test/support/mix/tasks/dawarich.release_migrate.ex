defmodule Mix.Tasks.Dawarich.ReleaseMigrate do
  use Mix.Task

  alias Dawarich.{ReleaseMigrations, ReleaseMigrator}

  @shortdoc "Runs the Ecto release migrator against PHOENIX_TEST_DATABASE"

  @impl true
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: [only: :string])
    Mix.Task.run("app.config")
    config = Application.fetch_env!(:dawarich, Dawarich.Repo)

    Application.put_env(
      :dawarich,
      Dawarich.Repo,
      Keyword.merge(config, pool: DBConnection.ConnectionPool, timeout: :infinity)
    )

    :ok = Dawarich.Release.migrate()

    {:ok, result, _started} =
      Ecto.Migrator.with_repo(Dawarich.Repo, &migrate(&1, opts[:only]), pool_size: 3)

    report(result)
  end

  defp migrate(repo, nil), do: ReleaseMigrator.migrate(repo)

  defp migrate(repo, release) do
    case ReleaseMigrations.find(release) do
      nil -> {:error, {:unknown_release, release}}
      module -> ReleaseMigrator.apply_release_for_proof(repo, module)
    end
  end

  defp report({:ok, summary}) do
    Enum.each(summary.applied, &Mix.shell().info("applied #{&1}"))
    Enum.each(Map.get(summary, :pending_data, []), &Mix.shell().info("pending data #{&1}"))
  end

  defp report({:error, reason}), do: Mix.raise(describe(reason))

  @doc false
  defdelegate describe(reason), to: Dawarich.CLI.Migrate
end
