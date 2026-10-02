defmodule Dawarich.Families.History do
  @moduledoc false

  alias Dawarich.{I18n, RailsTime, Repo}
  alias Dawarich.Families.{Clock, Locations, Sharing}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.Api.Params

  @windows %{"24h" => "24 hours", "7d" => "7 days", "30d" => "30 days", "all" => "1 year"}

  @points """
  WITH b AS (
    SELECT GREATEST($2::text::timestamptz, $4::timestamptz - $5::text::interval,
                    CASE WHEN $7 THEN NULL ELSE $6::timestamp AT TIME ZONE 'UTC' END) AS lo,
           $3::text::timestamptz AS hi
  ), n AS (
    SELECT p.timestamp, p.lonlat, ROW_NUMBER() OVER (ORDER BY p.timestamp ASC) - 1 AS row_num,
           COUNT(*) OVER () AS total
    FROM points p, b
    WHERE p.user_id = $1 AND p.timestamp IS NOT NULL AND p.lonlat IS NOT NULL
      AND (p.anomaly = false OR p.anomaly IS NULL) AND b.lo < b.hi
      AND p.timestamp >= floor(extract(epoch FROM b.lo)) AND p.timestamp <= floor(extract(epoch FROM b.hi))
  )
  SELECT ST_Y(lonlat::geometry), ST_X(lonlat::geometry), timestamp FROM n
  WHERE total <= 5000 OR mod(row_num, ceil(total / 5000.0)::bigint) = 0
  ORDER BY timestamp ASC
  """

  def read(user, params, now) do
    case Locations.membership(user.id) do
      [_settings, nil] ->
        {:ok, 404, Locations.not_in_family()}

      [_settings, family_id] ->
        if Ruby.blank?(params["start_at"]) or Ruby.blank?(params["end_at"]),
          do: {:ok, 400, error("start_at_and_end_at_are_required")},
          else: members(user, family_id, stamp(params["start_at"]), stamp(params["end_at"]), now)
    end
  end

  defp members(user, family_id, from, to, now) do
    RailsTime.with_zone(user.timezone, fn ->
      sharing = for m <- Locations.members(family_id), Sharing.enabled?(m.settings, now), do: m
      {:ok, 200, {:object, [{"members", Enum.flat_map(sharing, &member(&1, from, to, now))}]}}
    end)
  end

  defp member(member, from, to, now) do
    config = Sharing.config(member.settings)
    started = if config["share_history"] == true, do: Clock.parse(config["started_at"])
    before = config["history_before_sharing"] == true

    with true <- config["share_history"] == true,
         true <- started != nil or before,
         [_ | _] = points <- points(member.id, from, to, now, config, started, before) do
      [
        {:object,
         [
           {"user_id", member.id},
           {"email", member.email},
           {"email_initial", Locations.initial(member.email)},
           {"sharing_since", Clock.iso(started)},
           {"points", points}
         ]}
      ]
    else
      _ -> []
    end
  end

  defp points(id, from, to, now, config, started, before) do
    window = Map.get(@windows, config["history_window"] || "7d", "7 days")
    Repo.query!(@points, [id, from, to, now, window, started, before]).rows
  end

  defp stamp(value) do
    case Params.timestamp(value) do
      {:ok, {:text, text}} -> text
      _other -> raise ArgumentError, "history time outside the strict shapes"
    end
  end

  defp error(key),
    do: {:object, [{"error", I18n.en!("controllers.api.v1.families.locations." <> key)}]}
end
