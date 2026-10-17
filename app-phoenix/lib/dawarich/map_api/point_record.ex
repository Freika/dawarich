defmodule Dawarich.MapApi.PointRecord do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo, TtlCache}
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  @excluded ~w(created_at updated_at visit_id import_id user_id raw_data country_id source_id lock_version)
  @serialized ~w(id accuracy altitude altitude_decimal anomaly battery battery_status bssid city connection country country_name course course_accuracy external_track_id geodata in_regions inrids lonlat mode motion_data ping raw_data_archive_id raw_data_archived reverse_geocoded_at ssid timestamp topic track_id tracker_id trigger velocity vertical_accuracy)
  @schema Enum.sort(@serialized ++ @excluded)
  @dimensions ~w(tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)
  @slim ~w(id latitude longitude timestamp velocity country_name tracker_id)
  @enums %{
    "battery_status" => ~w(unknown unplugged charging full connected_not_charging discharging),
    "trigger" =>
      ~w(unknown background_event circular_region_event beacon_event report_location_message_event manual_event timer_based_event settings_monitoring_event),
    "connection" => %{0 => "mobile", 1 => "wifi", 2 => "offline", 4 => "unknown"}
  }

  @schema_ttl_ms :timer.minutes(1)

  def columns, do: columns(Repo)

  def columns(names) when is_list(names) do
    names = names -- ~w(latitude longitude)

    if Enum.sort(names) == @schema,
      do: {:ok, names -- @excluded},
      else: {:replay, "points columns outside the known schema"}
  end

  def columns(repo) when is_atom(repo) do
    load = fn -> catalogue(repo) end

    if :ets.whereis(TtlCache) == :undefined,
      do: load.(),
      else: TtlCache.fetch(cache_key(repo), @schema_ttl_ms, load)
  end

  def invalidate(repo \\ Repo), do: TtlCache.delete(cache_key(repo))

  defp catalogue(repo) do
    repo.query!(
      "SELECT attname::text FROM pg_attribute WHERE attrelid = 'public.points'::regclass " <>
        "AND attnum > 0 AND NOT attisdropped ORDER BY attnum"
    ).rows
    |> List.flatten()
    |> columns()
  end

  defp cache_key(repo) do
    dynamic = repo.get_dynamic_repo()
    process = if is_atom(dynamic), do: Process.whereis(dynamic), else: dynamic
    {__MODULE__, repo, dynamic, process}
  end

  def joins,
    do:
      " LEFT JOIN countries c ON c.id = p.country_id LEFT JOIN point_sources s ON s.id = p.source_id "

  def select_sql(true), do: select(~w(id timestamp velocity country_name tracker_id), "")

  def select_sql(false),
    do: select(@serialized -- ["lonlat"], ", p.lock_version AS revision")

  def ordered_json(text), do: text |> Jason.decode!(objects: :ordered_objects) |> json_term()

  defp select(names, extra) do
    Enum.map_join(names, ", ", &(expression(&1) <> " AS " <> &1)) <>
      ", ST_X(p.lonlat::geometry) AS longitude, ST_Y(p.lonlat::geometry) AS latitude" <> extra
  end

  def term(row, _columns, true), do: object(@slim, row)

  def term(%{"longitude" => nil}, _columns, false),
    do: raise(ArgumentError, "the full point serializer needs a geometry")

  def term(row, columns, false) do
    wkt = "POINT (#{RubyFloat.to_s(row["longitude"])} #{RubyFloat.to_s(row["latitude"])})"
    object(columns ++ ~w(latitude longitude revision), Map.put(row, "lonlat", wkt))
  end

  defp expression(name) when name in @dimensions,
    do: "CASE WHEN p.source_id IS NULL THEN p.#{name} ELSE s.#{name} END"

  defp expression("country_name"), do: "COALESCE(p.country_name, c.name, p.country, '')"
  defp expression("reverse_geocoded_at"), do: RailsTime.sql("p.reverse_geocoded_at", 3)
  defp expression(name) when name in ~w(geodata motion_data), do: "p.#{name}::text"
  defp expression(name), do: "p.#{name}"

  defp object(names, row), do: {:object, Enum.map(names, &{&1, value(&1, row[&1])})}

  defp value(name, nil) when name in ~w(latitude longitude), do: ""
  defp value(name, number) when name in ~w(latitude longitude), do: RubyFloat.to_s(number)
  defp value(_name, nil), do: nil

  defp value(name, text) when name in ~w(geodata motion_data), do: ordered_json(text)

  defp value(_name, %Decimal{} = number) do
    text = number |> Decimal.normalize() |> Decimal.to_string(:normal)
    if String.contains?(text, "."), do: text, else: text <> ".0"
  end

  defp value(name, number) when is_map_key(@enums, name) and is_integer(number) do
    case @enums[name] do
      labels when is_list(labels) and number >= 0 -> Enum.at(labels, number)
      labels when is_list(labels) -> nil
      labels -> labels[number]
    end
  end

  defp value(_name, value), do: value

  defp json_term(%Jason.OrderedObject{values: pairs}),
    do: {:object, Enum.map(pairs, fn {key, value} -> {key, json_term(value)} end)}

  defp json_term(values) when is_list(values), do: Enum.map(values, &json_term/1)
  defp json_term(value), do: value
end
