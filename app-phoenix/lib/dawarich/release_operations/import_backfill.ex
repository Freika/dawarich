defmodule Dawarich.ReleaseOperations.ImportBackfill do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.Imports.{ActivityBackfiller, ZonePeriod}
  alias Dawarich.Jobs.Processed
  alias Dawarich.TimeZoneName
  alias Dawarich.Tracks.ImportReprocessor

  def args_from_command(1, %{"import_id" => id, "ambient_zone" => zone} = payload)
      when map_size(payload) == 2 and is_integer(id) and id > 0 and is_binary(zone) and
             byte_size(zone) <= 128 do
    ZonePeriod.load!(TimeZoneName.to_iana(zone))
    {:ok, Map.put(payload, "version", 1)}
  rescue
    _ in [ArgumentError, File.Error] -> {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1, "event_id" => _} = args}),
    do: run(Dawarich.Jobs.repo(), args)

  def perform(_), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)

  def run(
        repo,
        %{"version" => 1, "event_id" => event, "import_id" => id, "ambient_zone" => zone},
        context \\ %{}
      ) do
    unless Processed.done?(repo, event) do
      if supported?(repo, id) do
        context = Map.put(context, :zone, TimeZoneName.to_iana(zone))
        ActivityBackfiller.call(repo, id, context)
        ImportReprocessor.run(repo, id, now: Map.get(context, :now))
      end

      Processed.mark!(repo, event, "release.import_backfill")
    end

    :ok
  end

  defp supported?(repo, id) do
    case repo.query!("SELECT source FROM imports WHERE id=$1", [id], log: false).rows do
      [[source]] when source in [0, 1, 2, 3, 6] -> true
      _ -> false
    end
  end
end
