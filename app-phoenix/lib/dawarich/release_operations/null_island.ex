defmodule Dawarich.ReleaseOperations.NullIsland do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.{RailsCommands, ReleaseOperations}

  @predicate "ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, 5000)"
  @users """
  SELECT u.id FROM users u
  WHERE u.deleted_at IS NULL AND u.id > $1
    AND u.id IN (SELECT DISTINCT user_id FROM points WHERE #{@predicate})
  ORDER BY u.id LIMIT 1000
  """
  @flag "UPDATE points SET anomaly = true, updated_at = now() WHERE user_id = $1 AND #{@predicate}"

  def command_type, do: "release.null_island"
  def predicate, do: @predicate

  def args_from_command(1, %{"user_id" => nil} = payload) when map_size(payload) == 1,
    do: {:ok, %{"version" => 1, "cursor" => %{"after_id" => 0}}}

  def args_from_command(1, %{"user_id" => user_id} = payload)
      when map_size(payload) == 1 and is_integer(user_id),
      do: {:ok, %{"version" => 1, "user_id" => user_id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1, "user_id" => user_id}}) when is_integer(user_id),
    do: flag(Dawarich.Jobs.repo(), user_id)

  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def step(repo, %{cursor: %{"after_id" => after_id}} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      ids = ReleaseOperations.ids(repo, @users, [after_id])
      Enum.each(ids, &Oban.insert!(op.oban, new(%{"version" => 1, "user_id" => &1})))
      if length(ids) < 1000, do: :done, else: {%{"after_id" => List.last(ids)}, 0}
    end)
  end

  def flag(repo, user_id) do
    if ReleaseOperations.user?(repo, user_id) do
      repo.transaction(fn ->
        repo.query!(@flag, [user_id], log: false)
        RailsCommands.insert!(repo, "release_null_island_follow_up", %{"user_id" => user_id})
      end)
    end

    :ok
  end
end
