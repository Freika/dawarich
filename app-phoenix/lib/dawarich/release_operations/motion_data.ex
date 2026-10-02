defmodule Dawarich.ReleaseOperations.MotionData do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseOperations
  alias Dawarich.ReleaseOperations.MotionExtractor

  @page """
  SELECT id, raw_data FROM points
  WHERE motion_data = '{}'::jsonb AND raw_data <> '{}'::jsonb AND id > $1
  ORDER BY id LIMIT $2
  """
  @update """
  UPDATE points p
  SET motion_data = v.motion_data,
      updated_at = CASE WHEN p.motion_data IS NOT DISTINCT FROM v.motion_data THEN p.updated_at ELSE now() END
  FROM unnest($1::bigint[], $2::jsonb[]) AS v(id, motion_data)
  WHERE p.id = v.id
  """

  def command_type, do: "release.motion_data"

  def args_from_command(1, %{"batch_size" => size} = payload)
      when map_size(payload) == 1 and is_integer(size) and size > 0,
      do: {:ok, %{"version" => 1, "cursor" => %{"after_id" => 0, "batch_size" => size}}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def step(repo, %{cursor: %{"after_id" => after_id, "batch_size" => size} = cursor} = op) do
    rows = repo.query!(@page, [after_id, size], log: false).rows

    updates =
      for [id, raw] <- rows,
          motion = MotionExtractor.from_raw_data(raw),
          motion != %{},
          do: {id, motion}

    ReleaseOperations.commit(repo, op, fn ->
      if updates != [] do
        {ids, motions} = Enum.unzip(updates)
        repo.query!(@update, [ids, motions], log: false)
      end

      case rows do
        [] -> :done
        _ -> {%{cursor | "after_id" => rows |> List.last() |> hd()}, 0}
      end
    end)
  end
end
