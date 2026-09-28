defmodule Dawarich.Achievements.Checker do
  @moduledoc false

  alias Dawarich.Achievements.{Dwell, Notices}
  alias Dawarich.RubyInteger

  @calculation_version 3
  @commit_attempts 2
  @eligible ~s|user_id = $1 AND lonlat IS NOT NULL AND (anomaly IS DISTINCT FROM TRUE)|

  def run(repo, user_id, notify, oldest, hook \\ fn _stage -> :ok end) do
    case settings(repo, user_id) do
      :missing ->
        :missing

      {:ok, settings} ->
        notify = notify and current_exploration?(repo, user_id)

        case progress_id(repo, user_id) do
          nil ->
            if scalar(repo, "SELECT EXISTS (SELECT 1 FROM points WHERE " <> @eligible <> ")", [
                 user_id
               ]),
               do:
                 check(
                   repo,
                   user_id,
                   settings,
                   create_progress!(repo, user_id),
                   notify,
                   oldest,
                   hook
                 ),
               else: :ok

          id ->
            check(repo, user_id, settings, id, notify, oldest, hook)
        end
    end
  end

  def threshold_seconds(settings) do
    value = if is_map(settings), do: Map.get(settings, "min_minutes_spent_in_city", 60), else: 60
    RubyInteger.to_i(value || 60) * 60
  end

  def merged_state(state, deltas, replace, cursor, inserted, threshold, now) do
    base = if replace, do: %{}, else: Map.get(state, "dwell", %{})

    dwell =
      Enum.reduce(deltas, base, fn {code, delta}, acc ->
        Map.update(acc, code, delta, &(&1 + delta))
      end)

    earned = Map.get(state, "earned", %{})

    codes =
      for(
        {code, seconds} <- dwell,
        not Map.has_key?(earned, code),
        seconds >= threshold,
        do: code
      )
      |> Enum.sort()

    merged =
      state
      |> Map.delete("point_id_cursor")
      |> Map.merge(%{
        "cursor" => cursor,
        "inserted_through" => inserted,
        "dwell" => dwell,
        "earned" => Map.merge(earned, Map.new(codes, &{&1, now})),
        "threshold_seconds" => threshold,
        "calculation_version" => @calculation_version
      })

    {merged, codes}
  end

  defp check(repo, user_id, settings, id, notify, oldest, hook) do
    newly =
      attempt(
        repo,
        user_id,
        id,
        oldest,
        threshold_seconds(settings),
        notify,
        hook,
        @commit_attempts
      )

    Notices.award_and_notify(repo, user_id, settings, id, newly, notify)
  end

  defp attempt(_repo, _user_id, _id, _oldest, _threshold, _notify, _hook, 0), do: []

  defp attempt(repo, user_id, id, oldest, threshold, notify, hook, left) do
    state = state(repo, id, "")
    previous = RubyInteger.to_i(state["cursor"])
    previous_inserted = state["inserted_through"]

    case latest_position(repo, user_id, previous, previous_inserted, oldest) do
      {nil, nil} ->
        []

      {cursor, inserted} ->
        pos = %{
          previous: previous,
          previous_inserted: previous_inserted,
          cursor: cursor,
          inserted: inserted,
          oldest: oldest
        }

        if settled?(repo, user_id, pos, state, threshold) do
          []
        else
          replace = recompute?(repo, user_id, pos) or calculation_changed?(state)

          deltas =
            if threshold_changed?(state, threshold) and cursor <= previous and not replace,
              do: %{},
              else: Dwell.deltas(repo, user_id, if(replace, do: 0, else: previous), cursor)

          hook.(:before_commit)

          case commit(repo, user_id, id, deltas, replace, pos, threshold, notify) do
            {:committed, codes} -> codes
            :conflict -> attempt(repo, user_id, id, oldest, threshold, notify, hook, left - 1)
          end
        end
    end
  end

  defp latest_position(repo, user_id, cursor, inserted_through, oldest) do
    latest_insert =
      scalar(repo, "SELECT max(created_at) FROM points WHERE " <> @eligible, [user_id])

    if is_nil(latest_insert) and cursor == 0 and is_nil(inserted_through) do
      {nil, nil}
    else
      since = inserted_through && parse!(inserted_through)

      latest_timestamp =
        cond do
          not is_nil(oldest) ->
            scalar(repo, ~s|SELECT max("timestamp") FROM points WHERE | <> @eligible, [user_id])

          latest_insert && (is_nil(since) or NaiveDateTime.compare(latest_insert, since) == :gt) ->
            scalar(
              repo,
              ~s|SELECT max("timestamp") FROM points WHERE | <>
                @eligible <>
                " AND ($2::timestamp IS NULL OR created_at > $2) AND created_at <= $3",
              [user_id, since, latest_insert]
            )

          true ->
            nil
        end

      {max(cursor, min(RubyInteger.to_i(latest_timestamp), System.os_time(:second))),
       watermark([since, latest_insert])}
    end
  end

  defp recompute?(repo, user_id, pos) do
    (not is_nil(pos.oldest) and pos.previous > 0 and pos.oldest <= pos.previous) or
      (pos.previous > 0 and pos.inserted != pos.previous_inserted and
         scalar(
           repo,
           "SELECT EXISTS (SELECT 1 FROM points WHERE " <>
             @eligible <>
             ~s| AND ($2::timestamp IS NULL OR created_at > $2) AND created_at <= $3 AND "timestamp" < $4)|,
           [
             user_id,
             pos.previous_inserted && parse!(pos.previous_inserted),
             parse!(pos.inserted),
             pos.previous
           ]
         ))
  end

  defp settled?(repo, user_id, pos, state, threshold) do
    pos.previous > 0 and pos.cursor <= pos.previous and pos.inserted == pos.previous_inserted and
      not recompute?(repo, user_id, pos) and not threshold_changed?(state, threshold) and
      RubyInteger.to_i(state["calculation_version"]) >= @calculation_version
  end

  defp threshold_changed?(state, threshold),
    do: RubyInteger.to_i(state["threshold_seconds"]) != threshold

  defp calculation_changed?(state),
    do: RubyInteger.to_i(state["calculation_version"]) < @calculation_version

  defp commit(repo, user_id, id, deltas, replace, pos, threshold, notify) do
    {:ok, outcome} =
      repo.transaction(fn ->
        current = state(repo, id, " FOR UPDATE")

        if RubyInteger.to_i(current["cursor"]) == pos.previous and
             current["inserted_through"] == pos.previous_inserted do
          now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
          cursor = max(pos.cursor, pos.previous)

          {merged, codes} =
            merged_state(current, deltas, replace, cursor, pos.inserted, threshold, now)

          repo.query!(
            "UPDATE achievement_progresses SET state = $2, updated_at = now() WHERE id = $1",
            [id, merged],
            log: false
          )

          if notify, do: Notices.unlock_geographies!(repo, user_id, codes)
          {:committed, codes}
        else
          :conflict
        end
      end)

    outcome
  end

  defp watermark(times) do
    case Enum.reject(times, &is_nil/1) do
      [] ->
        nil

      present ->
        %NaiveDateTime{microsecond: {us, _}} = latest = Enum.max(present, NaiveDateTime)

        latest
        |> Map.put(:microsecond, {us, 6})
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_iso8601()
    end
  end

  defp parse!(iso) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(iso)
    DateTime.to_naive(datetime)
  end

  defp settings(repo, user_id) do
    case repo.query!("SELECT settings FROM users WHERE id = $1 AND deleted_at IS NULL", [user_id],
           log: false
         ).rows do
      [[settings]] -> {:ok, if(is_map(settings), do: settings, else: %{})}
      [] -> :missing
    end
  end

  defp current_exploration?(repo, user_id),
    do:
      scalar(
        repo,
        "SELECT EXISTS (SELECT 1 FROM achievement_progresses WHERE user_id = $1 AND achievement_key = 'exploration' " <>
          "AND COALESCE((state ->> 'calculation_version')::integer, 0) >= $2)",
        [user_id, @calculation_version]
      )

  defp progress_id(repo, user_id),
    do:
      scalar(
        repo,
        "SELECT id FROM achievement_progresses WHERE user_id = $1 AND achievement_key = 'exploration'",
        [user_id]
      )

  defp create_progress!(repo, user_id) do
    repo.query!(
      "INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, created_at, updated_at) " <>
        "VALUES ($1, 'exploration', '{}', false, now(), now()) ON CONFLICT (user_id, achievement_key) DO NOTHING",
      [user_id],
      log: false
    )

    progress_id(repo, user_id)
  end

  defp state(repo, id, lock) do
    %{rows: [[state]]} =
      repo.query!("SELECT state FROM achievement_progresses WHERE id = $1" <> lock, [id],
        log: false
      )

    state
  end

  defp scalar(repo, sql, params) do
    case repo.query!(sql, params, log: false).rows do
      [[value]] -> value
      [] -> nil
    end
  end
end
