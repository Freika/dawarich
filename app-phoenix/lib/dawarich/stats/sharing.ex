defmodule Dawarich.Stats.Sharing do
  @moduledoc false
  alias Dawarich.{Accounts, Digests, Repo, Stats}
  alias Dawarich.Digests.Sharing

  def update(repo, user, year, month, attrs, context) do
    repo.transaction(fn ->
      case repo.query!(
             "SELECT id, sharing_uuid::text FROM stats WHERE user_id=$1 AND year=$2 AND month=$3 LIMIT 1 FOR UPDATE",
             [user.id, Digests.to_i(year), Digests.to_i(month)],
             log: false
           ).rows do
        [[id, uuid]] ->
          if Digests.to_i(month) not in 1..12, do: raise(ArgumentError, "invalid month")
          settings = Sharing.settings(repo, user.settings, attrs, context.now)
          uuid = uuid || Ecto.UUID.generate()

          repo.query!(
            "UPDATE stats SET sharing_settings=$2, sharing_uuid=$3, updated_at=$4 WHERE id=$1",
            [id, settings, Ecto.UUID.dump!(uuid), DateTime.to_naive(context.now)],
            log: false
          )

          Sharing.response(uuid, settings, context, "stats", "month")

        [] ->
          :not_found
      end
    end)
    |> case do
      {:ok, :not_found} -> :not_found
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  def get(uuid, now) do
    with {:ok, value} <- Ecto.UUID.dump(uuid),
         [[id, year, month, settings, h3]] <-
           Repo.query!(
             "SELECT user_id, year, month, sharing_settings, h3_hex_ids FROM stats WHERE sharing_uuid=$1 LIMIT 1",
             [value],
             log: false
           ).rows,
         true <- Sharing.public?(settings, now) do
      user = Accounts.get(id)
      context = %{Stats.context(user, now, true) | cutoff: nil}
      stat = Stats.month(user, year, month, context).stat

      %{
        user: user,
        stat: stat,
        bounds: bounds(id, year, month, context.zone),
        hexagons: (is_map(h3) and map_size(h3) > 0) or (is_list(h3) and h3 != [])
      }
    else
      _ -> nil
    end
  end

  defp bounds(id, year, month, zone) do
    [[min_lat, max_lat, min_lng, max_lng, count]] =
      Repo.query!(
        "SELECT min(ST_Y(lonlat::geometry)), max(ST_Y(lonlat::geometry)), min(ST_X(lonlat::geometry)), max(ST_X(lonlat::geometry)), count(*) FROM points WHERE user_id=$1 AND lonlat IS NOT NULL AND timestamp BETWEEN extract(epoch FROM (make_date($2,$3,1)::timestamp - interval '2 days')) AND extract(epoch FROM (make_date($2,$3,1)::timestamp + interval '1 month 2 days' - interval '1 microsecond')) AND extract(year FROM to_timestamp(timestamp) AT TIME ZONE $4)=$2 AND extract(month FROM to_timestamp(timestamp) AT TIME ZONE $4)=$3",
        [id, year, month, zone],
        log: false
      ).rows

    if count > 0,
      do: %{
        min_lat: min_lat,
        max_lat: max_lat,
        min_lng: min_lng,
        max_lng: max_lng,
        point_count: count
      }
  end
end
