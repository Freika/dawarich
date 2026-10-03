defmodule Dawarich.Geocoding.ReversePointWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :reverse_geocoding,
    max_attempts: 4,
    unique: [keys: [:event_id, :cursor], period: :infinity, states: :all]

  require Logger

  alias Dawarich.Geocoding.{Config, PointFetch}
  alias Dawarich.State

  def args_from_command(1, %{"user_id" => uid, "point_ids" => ids, "force" => force} = p)
      when is_integer(uid) and is_list(ids) and ids != [] and length(ids) <= 100 and
             is_boolean(force) and map_size(p) == 3 do
    if Enum.all?(ids, &is_integer/1),
      do: {:ok, Map.put(p, "cursor", 0)},
      else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"point_ids" => ids, "cursor" => cursor, "force" => force} = args} = job
      ) do
    repo = Dawarich.Jobs.repo()
    config = Config.resolve(repo)

    deadline =
      System.monotonic_time(:millisecond) +
        Application.get_env(:dawarich, :geocoding_batch_budget_ms, 300_000)

    ids
    |> Enum.with_index()
    |> Enum.drop(cursor)
    |> Enum.reduce_while(:ok, fn {id, index}, :ok ->
      if index > cursor and System.monotonic_time(:millisecond) >= deadline do
        Oban.insert!(job.conf.name, new(Map.put(args, "cursor", index)))
        {:halt, :ok}
      else
        geocode(repo, config, id, force)
        {:cont, :ok}
      end
    end)
  end

  defp geocode(repo, config, id, force) do
    if config.enabled, do: PointFetch.run(repo, id, config, force)
  after
    unless force, do: release(repo, id)
  end

  defp release(repo, id) do
    State.unclaim(repo, "geocode:enq:Point:#{id}")
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.error(
        "event=geocoding.dedupe_release_failed point_id=#{id} reason=#{inspect(error)}"
      )
  end
end
