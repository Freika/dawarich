defmodule Dawarich.ReleaseOperations.AddPointDimensions do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 288

  require Logger

  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseOperations.PointBackfill

  defdelegate args_from_command(version, payload), to: Dawarich.ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1}} = job), do: run(Dawarich.Jobs.repo(), job)
  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def backoff(_job), do: 300

  def run(repo, job \\ %Oban.Job{}) do
    unless column?(repo), do: add_column(repo)

    if column?(repo) and ReleaseMigration.backfill_allowed?(), do: enqueue(repo)
    :ok
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] in [:lock_not_available, :query_canceled] and
           job.attempt >= (job.max_attempts || 288),
         do: log_exhaustion(error)

      reraise error, __STACKTRACE__
  end

  def log_exhaustion(_error) do
    Logger.error(
      "[AddPointDimensions] gave up after 288 attempts; add points.source_id when traffic is quiet: " <>
        "BEGIN; SET LOCAL lock_timeout = '5s'; " <>
        "ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer; COMMIT; " <>
        "then start DataMigrations::BackfillPointDimensionsJob.perform_later"
    )
  end

  defp column?(repo), do: ReleaseMigration.column?(repo, "points", "source_id")

  defp add_column(repo) do
    {:ok, :ok} =
      repo.transaction(fn ->
        repo.query!("SET LOCAL lock_timeout = '5s'", [], log: false)

        unless column?(repo),
          do:
            ReleaseMigration.sql!(
              repo,
              "ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer"
            )

        :ok
      end)
  end

  defp enqueue(repo) do
    {:ok, PointBackfill, args} =
      Dawarich.ReleaseJobs.decode("DataMigrations::BackfillPointDimensionsJob", [])

    repo.insert!(PointBackfill.new(args), prefix: "oban", log: false)
  end
end
