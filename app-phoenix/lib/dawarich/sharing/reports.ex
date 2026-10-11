defmodule Dawarich.Sharing.Reports do
  @moduledoc false
  alias Dawarich.{Digests, Entitlements, Stats, UserSettings}
  alias Dawarich.Analytics.Period
  alias Dawarich.Sharing.Delivery

  def load(kind, uuid, opts) when kind in [:digest, :month] do
    now = Delivery.now(opts)
    zone = Keyword.get(opts, :viewer_zone, Dawarich.UserTimeZone.name(%{"timezone" => ""}))

    hosted =
      Keyword.get(opts, :self_hosted, Dawarich.ReleaseMigration.self_hosted?(System.get_env()))

    reader = if kind == :digest, do: &Digests.Sharing.get/3, else: &Stats.Sharing.get/3
    target = {kind, uuid, zone}
    admitted = Delivery.admit(target, now)

    case admitted && reader.(uuid, now, zone) do
      nil ->
        {:error, :not_found}

      data ->
        unit = Period.unit(UserSettings.get(data.user))
        full = Entitlements.full_access?(data.user, hosted, now)

        with true <- Dawarich.Distance.unit?(unit),
             {:ok, page} <- project(kind, data, full, unit, opts) do
          Delivery.deliver(target, admitted, page, opts)
        else
          false -> {:error, :unsupported}
        end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def load(_, _, _), do: {:error, :invalid_input}

  defp project(:digest, data, full, unit, opts) do
    Digests.validate_summary!(data.digest)
    if full, do: Digests.validate_full!(data.digest)
    d = data.digest

    page =
      max(1, min(Dawarich.RubyInteger.to_i(Keyword.get(opts, :page, "1")), 1_000_000_000_000))

    totals = %{
      countries: Digests.countries_count(d.toponyms),
      cities: Digests.cities_count(d.toponyms),
      first_countries: length(d.first_time_countries),
      first_cities: length(d.first_time_cities)
    }

    digest =
      Map.take(d, [
        :year,
        :distance,
        :total_minutes,
        :yoy_distance_change,
        :total_countries_all_time,
        :total_cities_all_time,
        :total_distance_all_time
      ])

    digest =
      Map.merge(digest, %{
        toponyms:
          if(full,
            do:
              d.toponyms
              |> Enum.slice((page - 1) * 50, 50)
              |> Enum.map(fn item ->
                %{
                  "country" => item["country"],
                  "cities_count" => length(item["cities"] || []),
                  "cities" =>
                    Enum.take(item["cities"] || [], 5) |> Enum.map(&Map.take(&1, ["city"]))
                }
              end),
            else: []
          ),
        first_time_countries: Enum.take(d.first_time_countries, 50),
        first_time_cities: Enum.take(d.first_time_cities, 5),
        top_countries:
          if(full,
            do: Enum.take(d.top_countries, 3) |> Enum.map(&Map.take(&1, ~w(name minutes))),
            else: []
          ),
        monthly_distances: if(full, do: Enum.take(d.monthly_distances, 12), else: [])
      })

    {:ok,
     %{
       kind: :digest,
       digest: digest,
       full: full,
       unit: unit,
       totals: totals,
       page: page,
       more: full and length(d.toponyms) > page * 50
     }}
  end

  defp project(:month, data, _full, unit, _opts) do
    stat = Map.take(data.stat, [:year, :month, :distance, :daily, :flight_distance])

    places = Dawarich.Analytics.Period.narrow(data.stat.toponyms)
    visited = Dawarich.Stats.Toponyms.visited(places)

    totals = %{
      countries: length(visited),
      cities: length(Dawarich.Stats.Toponyms.cities(visited))
    }

    bounded =
      for item <- Enum.take(places, 50),
          do:
            item
            |> Map.put("cities_count", length(item["cities"]))
            |> Map.update!("cities", &Enum.take(&1, 5))

    stat = Map.put(stat, :toponyms, bounded)

    {:ok,
     %{
       kind: :month,
       timezone: Dawarich.UserTimeZone.zone(UserSettings.get(data.user)),
       stat: stat,
       totals: totals,
       unit: unit,
       bounds: data.bounds,
       hexagons: data.hexagons
     }}
  end
end
