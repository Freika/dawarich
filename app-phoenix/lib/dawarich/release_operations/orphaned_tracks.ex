defmodule Dawarich.ReleaseOperations.OrphanedTracks do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  require Logger

  alias Dawarich.{RailsCommands, ReleaseOperations}

  @batch 1_000
  @page """
  SELECT t.id FROM tracks t
  WHERE t.id > $1 AND NOT EXISTS (SELECT 1 FROM points p WHERE p.track_id = t.id)
  ORDER BY t.id LIMIT $2
  """
  @lock """
  SELECT t.id, t.user_id, floor(extract(epoch FROM t.start_at))::bigint, floor(extract(epoch FROM t.end_at))::bigint
  FROM tracks t
  WHERE t.id = ANY($1) AND NOT EXISTS (SELECT 1 FROM points p WHERE p.track_id = t.id)
  FOR UPDATE OF t
  """

  defdelegate args_from_command(version, payload), to: ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1}}), do: run(Dawarich.Jobs.repo())
  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  def run(repo, after_id \\ 0) do
    case ReleaseOperations.ids(repo, @page, [after_id, @batch]) do
      [] ->
        :ok

      ids ->
        delete_batch(repo, ids)
        run(repo, List.last(ids))
    end
  end

  defp delete_batch(repo, ids) do
    repo.transaction(fn ->
      rows = repo.query!(@lock, [ids], log: false).rows
      orphan_ids = Enum.map(rows, &hd/1)
      repo.query!("DELETE FROM track_segments WHERE track_id = ANY($1)", [orphan_ids], log: false)
      repo.query!("DELETE FROM tracks WHERE id = ANY($1)", [orphan_ids], log: false)

      for {user_id, owned} <- Enum.group_by(rows, &Enum.at(&1, 1)) do
        stamps = Enum.flat_map(owned, fn [_, _, start_ts, end_ts] -> [start_ts, end_ts] end)

        RailsCommands.insert!(repo, "tracks_changed", %{
          "user_id" => user_id,
          "created" => [],
          "updated" => [],
          "destroyed" => Enum.map(owned, &hd/1),
          "min_ts" => Enum.min(stamps),
          "max_ts" => Enum.max(stamps)
        })
      end
    end)
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :foreign_key_violation,
        do: Logger.info("event=tracks.orphan_delete_aborted count=#{length(ids)}"),
        else: reraise(error, __STACKTRACE__)
  end
end
