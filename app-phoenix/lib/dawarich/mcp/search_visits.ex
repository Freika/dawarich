defmodule Dawarich.Mcp.SearchVisits do
  @moduledoc false
  alias Dawarich.{Accounts, RailsTime, Repo}
  alias Dawarich.Tiles.Http
  alias Dawarich.Timeline.DayRows
  alias Dawarich.Mcp.Timeline

  def fetch(user, params) do
    query =
      params["query"]
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    cutoff = Http.window(user)

    sql =
      "FROM visits v LEFT JOIN places p ON p.id=v.place_id LEFT JOIN areas a ON a.id=v.area_id WHERE v.user_id=$1 AND v.deleted_at IS NULL AND v.status<>2 AND ($3::bigint IS NULL OR v.started_at >= to_timestamp($3)) AND (v.name ILIKE $2 OR p.name ILIKE $2 OR p.city ILIKE $2 OR p.country ILIKE $2 OR a.name ILIKE $2)"

    args = [user.id, "%#{query}%", cutoff]
    [[count]] = Repo.query!("SELECT count(*) " <> sql, args).rows

    ids =
      Repo.query!(
        "SELECT v.id " <> sql <> " ORDER BY v.started_at DESC LIMIT $4",
        args ++ [params["limit"] || 20]
      ).rows

    settings = Dawarich.UserSettings.get(%{settings: Accounts.settings(user.id)})
    user = Map.put(user, :settings, Map.put(settings, "timezone", user.timezone))

    visits =
      RailsTime.with_zone(user.timezone, fn ->
        Enum.map(ids, fn [id] ->
          rows = DayRows.visit(user, id)
          day = hd(rows.visits).day

          entry =
            Dawarich.Timeline.Days.build(rows, "km")
            |> Enum.find(&(&1.date == Date.to_iso8601(day)))
            |> Map.fetch!(:entries)
            |> hd()

          Timeline.entry(entry)
        end)
      end)

    {:ok, {:object, [{"total_count", count}, {"visits", visits}]}}
  end
end
