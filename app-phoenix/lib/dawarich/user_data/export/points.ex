defmodule Dawarich.UserData.Export.Points do
  @moduledoc false
  alias Dawarich.{RailsTime, UserData.Export.Monthly}

  @fields ~w(battery_status battery timestamp altitude velocity accuracy ping tracker_id topic trigger bssid ssid connection vertical_accuracy mode inrids in_regions raw_data city country geodata reverse_geocoded_at course course_accuracy external_track_id created_at updated_at)
  @source ~w(battery_status tracker_id topic trigger bssid ssid connection inrids in_regions)
  @text ~w(inrids in_regions raw_data geodata)
  @time ~w(reverse_geocoded_at created_at updated_at)

  def write(repo, user, dir, _context) do
    columns =
      Enum.map_join(@fields, ",", fn name ->
        field =
          if name in @source,
            do: "CASE WHEN p.source_id IS NULL THEN p.#{name} ELSE ps.#{name} END",
            else: "p.#{name}"

        cond do
          name in @time -> RailsTime.sql(field, 3)
          name in @text -> "(#{field})::text"
          true -> field
        end
      end)

    select =
      columns <>
        ",p.lonlat::text,ST_X(p.lonlat::geometry),ST_Y(p.lonlat::geometry),i.name,i.source," <>
        RailsTime.sql("i.created_at", 3) <>
        ",c.name,c.iso_a2,c.iso_a3,v.name," <>
        RailsTime.sql("v.started_at", 3) <>
        "," <>
        RailsTime.sql("v.ended_at", 3) <>
        ",to_char(to_timestamp(p.timestamp) AT TIME ZONE 'UTC','YYYY-MM')"

    rows =
      Stream.unfold(0, fn cursor ->
        batch =
          RailsTime.with_zone(repo, "UTC", fn ->
            repo.query!(
              "SELECT p.id,#{select} FROM points p LEFT JOIN point_sources ps ON ps.id=p.source_id LEFT JOIN imports i ON i.id=p.import_id AND i.user_id=$1 LEFT JOIN countries c ON c.id=p.country_id LEFT JOIN visits v ON v.id=p.visit_id AND v.user_id=$1 WHERE p.user_id=$1 AND p.id>$2 ORDER BY p.id LIMIT 1000",
              [user, cursor]
            ).rows
          end)

        case batch do
          [] -> nil
          rows -> {rows, rows |> List.last() |> hd()}
        end
      end)
      |> Stream.flat_map(& &1)
      |> Stream.reject(fn row -> is_nil(Enum.at(row, length(@fields) + 1)) end)
      |> Stream.map(&point/1)

    Monthly.write_rows(rows, "points", dir)
  end

  defp point([_id | values]) do
    {fields,
     [wkb, lon, lat, import, source, created, country, a2, a3, visit, started, ended, month]} =
      Enum.split(values, length(@fields))

    pairs =
      Enum.zip_with(@fields, fields, fn name, value ->
        value =
          cond do
            name in ~w(inrids in_regions) and is_nil(value) -> []
            true -> value
          end

        {name, value}
      end)

    pairs = pairs ++ [{"lonlat", wkb}, {"longitude", lon}, {"latitude", lat}]

    pairs =
      reference(pairs, "import_reference", import, [
        {"name", import},
        {"source", source},
        {"created_at", created}
      ])

    pairs =
      reference(pairs, "country_info", country, [
        {"name", country},
        {"iso_a2", a2},
        {"iso_a3", a3}
      ])

    pairs =
      reference(pairs, "visit_reference", visit, [
        {"name", visit},
        {"started_at", started},
        {"ended_at", ended}
      ])

    {month || "unknown", pairs}
  end

  defp reference(pairs, _key, nil, _values), do: pairs

  defp reference(pairs, key, _name, values),
    do: pairs ++ [{key, %Jason.OrderedObject{values: values}}]
end
