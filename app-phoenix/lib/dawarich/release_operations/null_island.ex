defmodule Dawarich.ReleaseOperations.NullIsland do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.{RailsCommands, ReleaseOperations}
  alias Dawarich.Points.NativeEffects

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

        if NativeEffects.native?(repo, "command:release.null_island"),
          do: follow_up(repo, user_id),
          else:
            RailsCommands.insert!(repo, "release_null_island_follow_up", %{"user_id" => user_id})
      end)
    end

    :ok
  end

  defp follow_up(repo, user_id) do
    rows =
      repo.query!(
        "SELECT timestamp,track_id FROM points WHERE user_id=$1 AND #{@predicate}",
        [user_id],
        log: false
      ).rows

    timestamps = Enum.map(rows, &hd/1)
    if rows != [], do: Dawarich.RailsEffects.tile_epoch(repo, user_id, timestamps)
    destroy_visits(repo, user_id)
    zone = System.get_env("TIME_ZONE", "Europe/Berlin") |> Dawarich.TimeZoneName.to_iana()

    months =
      repo.query!(
        "SELECT DISTINCT extract(year FROM to_timestamp(stamp) AT TIME ZONE $2)::int, " <>
          "extract(month FROM to_timestamp(stamp) AT TIME ZONE $2)::int " <>
          "FROM unnest($1::bigint[]) stamp WHERE stamp IS NOT NULL ORDER BY 1,2",
        [timestamps, zone],
        log: false
      ).rows

    for [year, month] <- months do
      payload = %{
        "user_id" => user_id,
        "year" => year,
        "month" => month,
        "notify_on_failure" => true
      }

      if NativeEffects.native?(repo, "command:stats.calculate_month"),
        do: NativeEffects.enqueue(repo, Dawarich.Stats.CalculateMonthWorker, payload),
        else:
          RailsCommands.insert!(
            repo,
            "stats.calculate_month",
            Map.put(payload, "run_at", System.os_time(:second))
          )
    end

    for track <- rows |> Enum.map(&List.last/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      payload = %{"track_id" => track}

      if NativeEffects.native?(repo, "command:tracks.recalculate"),
        do: NativeEffects.enqueue(repo, Dawarich.Tracks.RecalculateWorker, payload),
        else:
          RailsCommands.insert!(repo, "points.anomaly_recalculate", %{
            "user_id" => user_id,
            "track_id" => track,
            "job_queue" => nil
          })
    end

    :ok
  end

  defp destroy_visits(repo, user_id) do
    visits =
      repo.query!(
        "SELECT v.id,v.place_id,v.started_at,v.demo FROM visits v JOIN places p ON p.id=v.place_id " <>
          "WHERE v.user_id=$1 AND #{String.replace(@predicate, "lonlat", "p.lonlat")} FOR UPDATE OF v",
        [user_id],
        log: false
      ).rows

    ids = Enum.map(visits, &hd/1)
    repo.query!("UPDATE points SET visit_id=NULL WHERE visit_id=ANY($1)", [ids], log: false)
    repo.query!("DELETE FROM place_visits WHERE visit_id=ANY($1)", [ids], log: false)

    repo.query!(
      "DELETE FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1)",
      [ids],
      log: false
    )

    repo.query!("DELETE FROM visits WHERE id=ANY($1)", [ids], log: false)
    ordinary = Enum.reject(visits, fn [_id, _place, _stamp, demo] -> demo end)

    if ordinary != [] do
      Dawarich.RailsEffects.visit_months(
        repo,
        user_id,
        Enum.map(ordinary, fn [_id, _place, stamp, _demo] ->
          DateTime.from_naive!(stamp, "Etc/UTC")
        end)
      )

      Dawarich.RailsEffects.orphan_places(
        repo,
        user_id,
        Enum.map(ordinary, fn [_id, place, _stamp, _demo] -> place end)
      )
    end

    :ok
  end
end
