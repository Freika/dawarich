defmodule Dawarich.ReleaseOperations.Transportation do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.{RailsCommands, ReleaseOperations}

  @batch 1_000
  @slice 100
  @stagger 30
  @next_batch_delay 600
  @missing """
  SELECT DISTINCT t.id, t.user_id FROM tracks t
  JOIN users u ON u.id = t.user_id
  LEFT JOIN track_segments s ON s.track_id = t.id
  WHERE u.deleted_at IS NULL AND t.id > $1 AND (s.id IS NULL OR t.dominant_mode = 0)
  ORDER BY t.id LIMIT 1000
  """
  @all "SELECT t.id, t.user_id FROM tracks t WHERE t.id > $1 ORDER BY t.id LIMIT 1000"

  def command_type, do: "release.transportation"

  def args_from_command(1, %{"scope" => scope, "from_track_id" => from} = payload)
      when map_size(payload) == 2 and scope in ["missing", "all"] and is_integer(from),
      do: {:ok, %{"version" => 1, "cursor" => payload}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def step(repo, %{cursor: %{"scope" => scope, "from_track_id" => from}} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      rows = repo.query!(if(scope == "all", do: @all, else: @missing), [from], log: false).rows
      now = System.os_time(:second)

      rows
      |> Enum.chunk_every(@slice)
      |> Enum.with_index()
      |> Enum.each(fn {slice, index} -> enqueue(repo, slice, now + index * @stagger) end)

      advance(scope, rows)
    end)
  end

  defp enqueue(repo, slice, run_at) do
    for {user_id, track_ids} <- Enum.group_by(slice, &Enum.at(&1, 1), &hd/1) do
      RailsCommands.insert!(repo, "release_reclassify_tracks", %{
        "user_id" => user_id,
        "track_ids" => track_ids,
        "run_at" => run_at
      })
    end
  end

  defp advance(_scope, []), do: :done
  defp advance("missing", rows) when length(rows) < @batch, do: :done

  defp advance(scope, rows),
    do: {%{"scope" => scope, "from_track_id" => rows |> List.last() |> hd()}, @next_batch_delay}
end
