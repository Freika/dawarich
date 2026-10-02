defmodule Dawarich.Visits.RedetectWorker do
  @moduledoc false
  use Oban.Worker, queue: :visit_suggesting

  require Logger

  alias Dawarich.State.Lease
  alias Dawarich.Tracks.PerUserLock
  alias Dawarich.Visits.{Calendar, HistoryRedetect, RedetectNotifications, Settings, SmartDetect}

  @unique [keys: [:event_id, :step], period: :infinity, states: :all]
  @run_key_ttl_ms 21_600_000
  @user_lock_wait_ms 500
  @cooldown_sql "SELECT visits_redetected_at > now() - interval '1 hour' FROM users WHERE id = $1"
  @points_range_sql "SELECT min(timestamp), max(timestamp) FROM points WHERE user_id = $1"
  @complete_update "UPDATE users SET visits_redetected_at = now(), updated_at = now() WHERE id = $1"

  def args_from_command(1, %{"user_id" => id, "time_zone" => tz, "plan_restricted" => pr} = p)
      when is_integer(id) and is_binary(tz) and is_boolean(pr) and map_size(p) == 3,
      do: {:ok, Map.put(p, "step", "start")}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def new(args, opts), do: super(args, Keyword.merge(defaults(args), opts))

  defp defaults(%{"step" => "start"}), do: [priority: 3, max_attempts: 1, unique: @unique]
  defp defaults(_args), do: [priority: 3, max_attempts: 3, unique: @unique]

  @impl Oban.Worker
  def timeout(%Oban.Job{args: %{"step" => "start"}}), do: :timer.minutes(10)
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"step" => "start"} = args, conf: conf}),
    do: start(Dawarich.Jobs.repo(), conf.name, args)

  def perform(%Oban.Job{args: %{"step" => i} = args, conf: conf}) when is_integer(i),
    do: month(Dawarich.Jobs.repo(), conf.name, args)

  defp start(repo, oban, %{"user_id" => uid, "event_id" => event_id} = args) do
    if Settings.load(repo, uid), do: claim_and_run(repo, oban, run_key(uid), args), else: :ok
  rescue
    exception ->
      RedetectNotifications.failed(repo, uid, exception)
      release(repo, run_key(uid), event_id)
      reraise exception, __STACKTRACE__
  end

  defp claim_and_run(repo, oban, key, %{"user_id" => uid, "event_id" => event_id} = args) do
    cond do
      cooldown?(repo, uid) ->
        Logger.info("event=visits.redetect_start reason=cooldown_active user_id=#{uid}")
        :ok

      claim(repo, key, event_id) == :busy ->
        RedetectNotifications.busy(repo, uid)
        :ok

      true ->
        after_claim(repo, oban, key, args)
    end
  end

  defp after_claim(repo, oban, key, %{"user_id" => uid, "event_id" => event_id} = args) do
    if cooldown?(repo, uid) do
      Logger.info("event=visits.redetect_start reason=cooldown_active_after_lock user_id=#{uid}")
      release(repo, key, event_id)
      :ok
    else
      case points_range(repo, uid) do
        nil ->
          RedetectNotifications.no_points(repo, uid)
          release(repo, key, event_id)
          :ok

        {min_ts, max_ts} ->
          purge_and_schedule(repo, oban, key, min_ts, max_ts, args)
      end
    end
  end

  defp purge_and_schedule(repo, oban, key, min_ts, max_ts, %{
         "user_id" => uid,
         "event_id" => event_id,
         "time_zone" => zone,
         "plan_restricted" => plan_restricted
       }) do
    purge = fn -> HistoryRedetect.purge(repo, uid, min_ts, max_ts) end

    case PerUserLock.with_user_lock(repo, uid, purge, timeout_ms: @user_lock_wait_ms) do
      {:ok, _wiped} ->
        months_total = length(Calendar.redetect_months(repo, zone, min_ts, max_ts))

        step0 = %{
          "user_id" => uid,
          "event_id" => event_id,
          "time_zone" => zone,
          "plan_restricted" => plan_restricted,
          "step" => 0,
          "min_ts" => min_ts,
          "max_ts" => max_ts,
          "months_total" => months_total,
          "visits_created" => 0,
          "months_failed" => 0
        }

        if months_total == 0,
          do: finalize(repo, key, event_id, step0),
          else: Oban.insert!(oban, new(step0))

      {:error, :timeout} ->
        RedetectNotifications.busy(repo, uid)
        release(repo, key, event_id)
    end

    :ok
  end

  defp month(repo, oban, %{"user_id" => uid, "event_id" => event_id} = args) do
    if Lease.renew(repo, run_key(uid), event_id, @run_key_ttl_ms) do
      run_month(repo, oban, run_key(uid), args)
    else
      Logger.info("event=visits.redetect_month reason=run_superseded user_id=#{uid}")
      :ok
    end
  end

  defp run_month(
         repo,
         oban,
         key,
         %{
           "user_id" => uid,
           "event_id" => event_id,
           "time_zone" => zone,
           "step" => i,
           "min_ts" => min_ts,
           "max_ts" => max_ts
         } = args
       ) do
    [start_ts, stop_ts] = Enum.at(Calendar.redetect_months(repo, zone, min_ts, max_ts), i)
    detect = fn -> detect_month(repo, uid, start_ts, stop_ts, args) end

    case PerUserLock.with_user_lock(repo, uid, detect, timeout_ms: @user_lock_wait_ms) do
      {:ok, {count, failed?}} -> advance(repo, oban, key, args, count, failed?)
      {:error, :timeout} -> {:snooze, 30}
    end
  rescue
    exception ->
      RedetectNotifications.failed(repo, uid, exception)
      release(repo, key, event_id)
      {:cancel, Exception.message(exception)}
  end

  defp detect_month(repo, uid, start_ts, stop_ts, args) do
    %{visits: visits, skipped_ranges: skipped} =
      SmartDetect.run(repo, uid, start_ts, stop_ts, args)

    {length(visits), skipped != []}
  rescue
    _exception -> {0, true}
  end

  defp advance(
         repo,
         oban,
         key,
         %{"event_id" => event_id, "step" => i, "months_total" => total} = args,
         count,
         failed?
       ) do
    next_args =
      args
      |> Map.update!("visits_created", &(&1 + count))
      |> Map.update!("months_failed", &(&1 + if(failed?, do: 1, else: 0)))

    if i + 1 < total,
      do: Oban.insert!(oban, new(%{next_args | "step" => i + 1})),
      else: finalize(repo, key, event_id, next_args)

    :ok
  end

  defp finalize(repo, key, event_id, %{
         "user_id" => uid,
         "visits_created" => created,
         "months_failed" => failed,
         "months_total" => total
       }) do
    HistoryRedetect.backfill(repo, uid, Settings.policy(Settings.load(repo, uid).settings))

    repo.transaction(fn ->
      if failed == 0 do
        repo.query!(@complete_update, [uid], log: false)
        RedetectNotifications.complete(repo, uid, created, total)
      else
        RedetectNotifications.partial(repo, uid, created, total - failed, total, failed)
      end
    end)

    release(repo, key, event_id)
  end

  defp claim(repo, key, token),
    do: if(Lease.acquire(repo, key, token, @run_key_ttl_ms), do: :ok, else: :busy)

  defp release(repo, key, token) do
    Lease.release(repo, key, token)
  rescue
    _ in [DBConnection.ConnectionError, Postgrex.Error] -> false
  end

  defp cooldown?(repo, uid), do: repo.query!(@cooldown_sql, [uid], log: false).rows == [[true]]

  defp points_range(repo, uid) do
    case repo.query!(@points_range_sql, [uid], log: false).rows do
      [[nil, nil]] -> nil
      [[min, max]] -> {min, max}
    end
  end

  defp run_key(uid), do: "visits:redetect_run:#{uid}"
end
