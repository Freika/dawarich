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
      module -> ReleaseMigrator.apply_release(repo, module)
    end
  end

  defp report({:ok, summary}) do
    Enum.each(summary.applied, &Mix.shell().info("applied #{&1}"))
    Enum.each(Map.get(summary, :pending_data, []), &Mix.shell().info("pending data #{&1}"))
  end

  defp report({:error, reason}), do: Mix.raise(describe(reason))

  @doc false
  def describe({:unknown_release, release}), do: "no Ecto release module for #{release}"

  def describe({:failed, release, version, message}),
    do: "failed #{release} #{version}: #{String.replace(message, ~r/\s+/, " ")}"

  def describe({:newer, versions}),
    do: "refused: newer than this image (#{Enum.join(versions, " ")})"

  def describe({:foreign_schema, schema, others}),
    do: "refused: Rails tables outside public (search path #{schema}; #{Enum.join(others, " ")})"

  def describe({:locked, holder}),
    do: "refused: another migrator holds the lease (#{holder})"

  def describe({:lease_lost, holder}), do: "refused: lease lost by #{holder}"
  def describe(:pool_too_small), do: "refused: the repo pool needs two connections"
  def describe({:timezone, value}), do: "refused: session time zone is #{value}, not UTC"

  def describe({:rails_migrating, pid}),
    do:
      "refused: a Rails migrator holds its advisory lock (backend #{pid}); stop it, or if no Rails process runs, " <>
        "wait for PgBouncer's server_lifetime or restart PgBouncer"
end
