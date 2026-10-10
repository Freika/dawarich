defmodule Dawarich.SharedApi.Points do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo, UserTimeZone}
  alias Dawarich.SharedApi.Privacy
  alias Dawarich.Spatial.CalendarWindow

  @false_flags [nil, false, "", "0", "false", "FALSE", "f", "F", "off", "OFF"]

  def live(link, now) do
    rows =
      Repo.query!(
        "SELECT ST_X(lonlat::geometry), ST_Y(lonlat::geometry), timestamp FROM points p " <>
          "WHERE user_id = $1 AND anomaly IS NOT TRUE ORDER BY timestamp DESC LIMIT 1",
        [link.user_id]
      ).rows

    case rows do
      [] ->
        {:ok, []}

      [[lon, lat, ts] | _] ->
        ts = ts || 0

        if DateTime.to_unix(now) - ts > 900 do
          {:ok, []}
        else
          lon = lon || 0.0
          lat = lat || 0.0
          point = "ST_SetSRID(ST_MakePoint($2::float8,$3::float8),4326)::geography"

          [[outside]] =
            Repo.query!("SELECT #{Privacy.outside(point)}", [link.user_id, lon, lat]).rows

          {:ok, if(outside, do: [[lon, lat, ts]], else: [])}
        end
    end
  end

  def route(%{type: "live"} = link) do
    if link.settings["show_route"] in @false_flags do
      {:ok, []}
    else
      from = link.created_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

      sample("p.user_id = $1 AND p.anomaly IS NOT TRUE AND p.timestamp >= $2", [
        link.user_id,
        from
      ])
    end
  end

  def route(_link), do: {:ok, []}

  def index(link) do
    [[settings]] = Repo.query!("SELECT settings FROM users WHERE id = $1", [link.user_id]).rows

    zone = UserTimeZone.name(settings)

    RailsTime.with_zone(zone, fn ->
      with {:ok, predicate, params} <- scope(link, zone),
           do: sample(predicate, params)
    end)
  end

  defp scope(%{type: "trip"} = link, _zone) do
    {:ok,
     "p.user_id = $1 AND p.anomaly IS NOT TRUE AND EXISTS (SELECT 1 FROM trips t " <>
       "WHERE t.id = $2 AND t.user_id = $1 AND p.timestamp BETWEEN " <>
       "extract(epoch FROM t.started_at)::bigint AND extract(epoch FROM t.ended_at)::bigint)",
     [link.user_id, link.resource_id]}
  end

  defp scope(%{type: "track"} = link, _zone) do
    {:ok,
     "p.track_id = $2 AND EXISTS (SELECT 1 FROM tracks t WHERE t.id = $2 AND t.user_id = $1)",
     [link.user_id, link.resource_id]}
  end

  defp scope(%{type: "timeline", settings: settings} = link, zone) do
    with {:ok, from} <- CalendarWindow.date(settings["start_date"], zone),
         {:ok, to} <- CalendarWindow.date(settings["end_date"], zone) do
      {first, last} = CalendarWindow.days(zone, from, to)

      {:ok, "p.user_id = $1 AND p.anomaly IS NOT TRUE AND p.timestamp BETWEEN $2 AND $3",
       [link.user_id, first, last]}
    else
      _ -> {:replay, "shared timeline dates"}
    end
  end

  defp scope(_link, _zone), do: {:replay, "shared points resource type"}

  defp sample(predicate, params) do
    from = " FROM points p WHERE #{predicate} AND #{Privacy.outside("p.lonlat")}"

    [[total]] = Repo.query!("SELECT count(*)" <> from, params).rows

    case total do
      0 ->
        {:ok, []}

      _ ->
        step = ceil(total / 10_000)

        numbered =
          "SELECT ST_X(p.lonlat::geometry) AS lon, ST_Y(p.lonlat::geometry) AS lat, " <>
            "p.timestamp, ROW_NUMBER() OVER (ORDER BY p.timestamp) AS rn" <> from

        rows =
          Repo.query!(
            "SELECT lon, lat, timestamp FROM (#{numbered}) sampled " <>
              "WHERE (rn - 1) % $#{length(params) + 1} = 0 ORDER BY timestamp",
            params ++ [step]
          ).rows

        {:ok, Enum.map(rows, fn [lon, lat, ts] -> [lon || 0.0, lat || 0.0, ts || 0] end)}
    end
  end
end
