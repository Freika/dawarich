defmodule Dawarich.Achievements.Position do
  @moduledoc false

  alias Dawarich.RubyInteger

  @eligible ~s|user_id = $1 AND lonlat IS NOT NULL AND (anomaly IS DISTINCT FROM TRUE)|

  def points?(repo, user_id),
    do: scan(repo, "SELECT EXISTS (SELECT 1 FROM points WHERE " <> @eligible <> ")", [user_id])

  def latest(repo, user_id, cursor, inserted_through, oldest) do
    latest_insert =
      scan(repo, "SELECT max(created_at) FROM points WHERE " <> @eligible, [user_id])

    if is_nil(latest_insert) and cursor == 0 and is_nil(inserted_through) do
      {nil, nil}
    else
      since = inserted_through && parse!(inserted_through)

      latest_timestamp =
        cond do
          not is_nil(oldest) ->
            scan(repo, ~s|SELECT max("timestamp") FROM points WHERE | <> @eligible, [user_id])

          latest_insert && (is_nil(since) or NaiveDateTime.compare(latest_insert, since) == :gt) ->
            scan(
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

  def recompute?(repo, user_id, pos) do
    (not is_nil(pos.oldest) and pos.previous > 0 and pos.oldest <= pos.previous) or
      (pos.previous > 0 and pos.inserted != pos.previous_inserted and
         scan(
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

  defp scan(repo, sql, params) do
    case repo.query!(sql, params, log: false, timeout: :infinity).rows do
      [[value]] -> value
      [] -> nil
    end
  end
end
