defmodule Dawarich.ReleaseOperations.VisitsFleetRedetect do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseOperations
  alias Dawarich.Visits.UserRedetectWorker

  @batch 500
  @stagger 30
  @page """
  SELECT id FROM users
  WHERE deleted_at IS NULL AND status = 1 AND points_count >= 1 AND id > $1
  ORDER BY id LIMIT 500
  """

  def command_type, do: "release.visits_fleet_redetect"

  def args_from_command(1, payload) when map_size(payload) == 0,
    do:
      {:ok, %{"version" => 1, "cursor" => %{"after_id" => 0, "started_at" => nil, "offset" => 0}}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def step(
        repo,
        %{cursor: %{"after_id" => after_id, "started_at" => started, "offset" => offset}} = op
      ) do
    started = started || System.os_time(:second)

    ReleaseOperations.commit(repo, op, fn ->
      ids = ReleaseOperations.ids(repo, @page, [after_id])

      ids
      |> Enum.with_index()
      |> Enum.each(fn {user_id, index} ->
        UserRedetectWorker.enqueue(repo, user_id, started + offset + index * @stagger, op.id)
      end)

      if length(ids) < @batch,
        do: :done,
        else:
          {%{
             "after_id" => List.last(ids),
             "started_at" => started,
             "offset" => offset + @batch * @stagger
           }, 0}
    end)
  end
end
