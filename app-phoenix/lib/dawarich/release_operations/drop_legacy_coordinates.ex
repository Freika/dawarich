defmodule Dawarich.ReleaseOperations.DropLegacyCoordinates do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 288

  require Logger

  alias Dawarich.ReleaseMigration

  defdelegate args_from_command(version, payload), to: Dawarich.ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1}} = job), do: run(Dawarich.Jobs.repo(), job)
  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def backoff(_job), do: 300

  def run(repo, job \\ %Oban.Job{}) do
    if legacy_columns?(repo) do
      {:ok, :ok} =
        repo.transaction(fn ->
          repo.query!("SET LOCAL statement_timeout = 0", [], log: false)
          repo.query!("SET LOCAL lock_timeout = '5s'", [], log: false)

          if legacy_columns?(repo) do
            ReleaseMigration.sql!(
              repo,
              "ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude"
            )
          end

          :ok
        end)
    end

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
      "[DropLegacyCoordinates] gave up after 288 attempts; drop legacy points columns when traffic is quiet: " <>
        "BEGIN; SET LOCAL lock_timeout = '5s'; " <>
        "ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude; COMMIT;"
    )
  end

  defp legacy_columns?(repo),
    do:
      ReleaseMigration.column?(repo, "points", "latitude") or
        ReleaseMigration.column?(repo, "points", "longitude")
end
