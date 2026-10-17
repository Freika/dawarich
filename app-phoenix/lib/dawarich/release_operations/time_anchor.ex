defmodule Dawarich.ReleaseOperations.TimeAnchor do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseOperations
  alias Dawarich.Transportation.Segments

  @page """
  SELECT id FROM track_segments
  WHERE id > $1 AND start_at IS NULL AND start_index IS NOT NULL
  ORDER BY id LIMIT 1000
  """
  @drop "DELETE FROM track_segments WHERE id = ANY($1) AND start_at IS NULL AND corrected_at IS NULL"

  def command_type, do: "release.time_anchor"

  def args_from_command(1, %{"from_id" => from} = payload)
      when map_size(payload) == 1 and is_integer(from),
      do: {:ok, %{"version" => 1, "cursor" => payload}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def step(repo, %{cursor: %{"from_id" => from}} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      case ReleaseOperations.ids(repo, @page, [from]) do
        [] ->
          :done

        ids ->
          Segments.anchor_now!(repo, ids)
          repo.query!(@drop, [ids], log: false)
          {%{"from_id" => List.last(ids)}, 0}
      end
    end)
  end
end
