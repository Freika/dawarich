defmodule Dawarich.Tracks.BackfillRanges do
  @moduledoc false

  @lookback 21_600
  @delay 60
  @columns ~w(user_id earliest_timestamp latest_timestamp cycle_id time_zone due_at expires_at inserted_at updated_at)a
  @upsert """
  INSERT INTO phoenix.track_backfill_ranges AS stored
    (user_id, earliest_timestamp, latest_timestamp, cycle_id, time_zone, due_at, expires_at, inserted_at, updated_at)
  VALUES ($1, $2, $3, $4, $5, $7, $8, $6, $6)
  ON CONFLICT (user_id) DO UPDATE SET
    earliest_timestamp = CASE WHEN stored.expires_at <= $6 THEN EXCLUDED.earliest_timestamp
      ELSE LEAST(stored.earliest_timestamp, EXCLUDED.earliest_timestamp) END,
    latest_timestamp = CASE WHEN stored.expires_at <= $6 THEN EXCLUDED.latest_timestamp
      ELSE GREATEST(stored.latest_timestamp, EXCLUDED.latest_timestamp) END,
    cycle_id = CASE WHEN stored.expires_at <= $6 OR NOT stored.scheduled THEN EXCLUDED.cycle_id ELSE stored.cycle_id END,
    time_zone = CASE WHEN stored.expires_at <= $6 THEN EXCLUDED.time_zone ELSE stored.time_zone END,
    due_at = CASE WHEN stored.expires_at <= $6 OR NOT stored.scheduled THEN EXCLUDED.due_at ELSE stored.due_at END,
    expires_at = EXCLUDED.expires_at,
    inserted_at = CASE WHEN stored.expires_at <= $6 THEN EXCLUDED.inserted_at ELSE stored.inserted_at END,
    updated_at = EXCLUDED.updated_at,
    scheduled = true
  RETURNING user_id, earliest_timestamp, latest_timestamp, cycle_id::text, time_zone,
    due_at, expires_at, inserted_at, updated_at
  """

  def put(repo, user_id, timestamps, time_zone, now, publish) do
    case Enum.reject(timestamps, &is_nil/1) do
      [] ->
        {:ok, :noop}

      values ->
        {earliest, latest} = Enum.min_max(values)

        if earliest < DateTime.to_unix(now) - @lookback do
          accumulate(repo, user_id, earliest, latest, time_zone, now, publish)
        else
          {:ok, :noop}
        end
    end
  end

  defp accumulate(repo, user_id, earliest, latest, time_zone, now, publish) do
    cycle_id = Ecto.UUID.generate()

    repo.transaction(fn ->
      [values] =
        repo.query!(
          @upsert,
          [
            user_id,
            earliest,
            latest,
            Ecto.UUID.dump!(cycle_id),
            time_zone,
            now,
            DateTime.add(now, @delay),
            DateTime.add(now, @lookback)
          ],
          log: false
        ).rows

      range = Map.new(Enum.zip(@columns, values))

      if range.cycle_id == cycle_id do
        case publish.(range) do
          {:error, reason} -> repo.rollback(reason)
          _ -> {:inserted, range}
        end
      else
        {:widened, range}
      end
    end)
  end
end
