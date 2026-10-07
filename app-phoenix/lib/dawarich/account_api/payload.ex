defmodule Dawarich.AccountApi.Payload do
  @moduledoc false

  alias Dawarich.{Accounts, RailsTime, Repo, UserSettings, UserTimeZone}
  alias Dawarich.AccountApi.Closure
  alias Dawarich.Geocoding.Config
  alias Dawarich.Ingest.Ruby

  @defaults %{
    "fog_of_war_meters" => 50,
    "meters_between_routes" => 500,
    "preferred_map_layer" => "OpenStreetMap",
    "speed_colored_routes" => false,
    "points_rendering_mode" => "raw",
    "minutes_between_routes" => 30,
    "time_threshold_minutes" => 30,
    "merge_threshold_minutes" => 15,
    "live_map_enabled" => true,
    "route_opacity" => 0.6,
    "immich_url" => nil,
    "photoprism_url" => nil,
    "visits_suggestions_enabled" => "true",
    "speed_color_scale" => nil,
    "fog_of_war_threshold" => 50,
    "globe_projection" => true
  }
  @keys ~w(timezone maps fog_of_war_meters meters_between_routes preferred_map_layer speed_colored_routes points_rendering_mode minutes_between_routes time_threshold_minutes merge_threshold_minutes live_map_enabled route_opacity immich_url photoprism_url visits_suggestions_enabled speed_color_scale fog_of_war_threshold globe_projection)

  def read(id, now \\ DateTime.utc_now()) do
    raw = Accounts.settings(id)
    raw = UserSettings.safe(raw)
    timezone = raw["timezone"] || System.get_env("TIME_ZONE", "UTC")
    unless is_binary(timezone), do: Ruby.unsupported!("account timezone shape")
    zone = UserTimeZone.name(raw)

    [[plan, status, source, active_until]] =
      Repo.query!("SELECT plan,status,subscription_source,active_until FROM users WHERE id=$1", [
        id
      ]).rows

    actor = %{
      id: id,
      plan: plan,
      status: status,
      subscription_source: source,
      active_until: active_until
    }

    full = Closure.full?(actor, now)

    RailsTime.with_zone(zone, fn ->
      [[email, theme, created, updated]] =
        Repo.query!(
          "SELECT email,theme,#{RailsTime.sql("created_at", 3)},#{RailsTime.sql("updated_at", 3)} FROM users WHERE id=$1",
          [id]
        ).rows

      settings = settings(raw, timezone, full)

      features =
        {:object,
         [
           {"reverse_geocoding", Config.resolve(Repo).enabled},
           {"family", Closure.family?(actor, now)}
         ]}

      user =
        {:object,
         [
           {"id", id},
           {"email", email},
           {"theme", theme},
           {"created_at", created},
           {"updated_at", updated},
           {"settings", settings}
         ]}

      fields = [{"user", user}, {"features", features}]

      fields =
        if Closure.hosted?(),
          do: fields,
          else: fields ++ [{"subscription", Closure.subscription(actor, stamp(active_until))}]

      {:ok, {:object, fields}}
    end)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp settings(raw, timezone, full) do
    values = Map.merge(@defaults, raw)

    maps =
      case raw["maps"] do
        nil -> if Map.has_key?(raw, "maps"), do: nil, else: %{"distance_unit" => "km"}
        value when is_map(value) -> Map.merge(%{"distance_unit" => "km"}, value)
        _ -> Ruby.unsupported!("maps container")
      end

    maps =
      if full or not is_map(maps),
        do: maps,
        else: Map.drop(maps, ~w(hidden_tile_categories disabled_poi_groups))

    values =
      values
      |> Map.put("timezone", timezone)
      |> Map.put("maps", maps)
      |> Map.update!("fog_of_war_meters", &Ruby.to_i/1)
      |> Map.update!("meters_between_routes", &positive(&1, 500))
      |> Map.update!("minutes_between_routes", &(positive(&1, 30) |> clamp(1, 1440)))
      |> Map.update!("time_threshold_minutes", &(Ruby.to_i(&1) |> clamp(1, 1440)))
      |> Map.update!("merge_threshold_minutes", &Ruby.to_i/1)
      |> Map.update!("route_opacity", &Ruby.to_f/1)
      |> Map.update!("visits_suggestions_enabled", &(&1 == "true"))
      |> Map.update!("globe_projection", &if(full, do: UserSettings.cast(&1), else: false))

    maps =
      if is_map(maps) do
        {:object, rest} = ordered(Map.delete(maps, "distance_unit"))
        {:object, [{"distance_unit", ordered(maps["distance_unit"])} | rest]}
      else
        maps
      end

    values = Map.put(values, "maps", maps)
    {:object, Enum.map(@keys, &{&1, ordered(values[&1])})}
  end

  defp ordered(value) when is_map(value),
    do:
      {:object,
       value
       |> Enum.sort_by(fn {key, _} -> {byte_size(key), key} end)
       |> Enum.map(fn {key, value} -> {key, ordered(value)} end)}

  defp ordered(value) when is_list(value), do: Enum.map(value, &ordered/1)
  defp ordered(value), do: value

  defp stamp(nil), do: nil

  defp stamp(value) do
    [[text]] = Repo.query!("SELECT " <> RailsTime.sql("$1::timestamp", 3), [value]).rows
    text
  end

  defp positive(value, default) do
    n = Ruby.to_i(value)
    if n > 0, do: n, else: default
  end

  defp clamp(value, low, high), do: max(low, min(high, value))
end
