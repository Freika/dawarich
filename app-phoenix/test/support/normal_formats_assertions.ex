defmodule Dawarich.Test.NormalFormatsAssertions do
  @moduledoc false
  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

  def assert_snapshot(c, repo) do
    import ExUnit.Assertions
    rows = fn sql, args -> repo.query!(sql, args, log: false).rows end
    data = c.expected["import"]
    source = Enum.find_index(@sources, &(&1 == data["source"]))

    assert rows.(
             "SELECT raw_points,doubles,processed,raw_data,status,error_message,source FROM imports WHERE id=$1",
             [c.import.id]
           ) ==
             [
               [
                 data["raw_points"],
                 data["doubles"],
                 data["processed"],
                 data["raw_data"],
                 Enum.find_index(
                   ~w(created processing completed failed deleting),
                   &(&1 == data["status"])
                 ),
                 data["error_message"],
                 source
               ]
             ]

    columns =
      ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)

    columns = if c.expected["legacy"], do: columns -- ["altitude_decimal"], else: columns

    select =
      Enum.map_join(columns, ",", fn
        "lonlat" ->
          "ST_AsText(lonlat::geometry)"

        key when key in ~w(altitude_decimal course course_accuracy) ->
          "CASE WHEN #{key}=trunc(#{key}) THEN trunc(#{key})::text||'.0' ELSE trim_scale(#{key})::text END"

        key ->
          key
      end)

    assert rows.("SELECT #{select} FROM points WHERE import_id=$1 ORDER BY id", [c.import.id]) ==
             Enum.map(c.expected["points"], &Enum.map(columns, fn key -> &1[key] end))

    assert rows.(
             "SELECT title,content,CASE kind WHEN 2 THEN 'error' WHEN 1 THEN 'warning' ELSE 'info' END FROM notifications WHERE user_id=$1 ORDER BY id",
             [c.import.user_id]
           ) == c.expected["notifications"]

    fields =
      ~w(digest tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)

    unless c.expected["legacy"] do
      assert rows.(
               "SELECT #{Enum.join(fields, ",")} FROM point_sources WHERE id IN (SELECT source_id FROM points WHERE import_id=$1) ORDER BY digest",
               [c.import.id]
             ) ==
               Enum.map(c.expected["sources"], &Enum.map(fields, fn key -> &1[key] end))
    end

    expected =
      Enum.map(c.expected["commands"], fn command ->
        payload = Map.put(command["payload"], "user_id", c.import.user_id)

        payload =
          if command["kind"] == "imports.progress",
            do: Map.put(payload, "import_id", c.import.id),
            else: payload

        [command["kind"], payload]
      end)

    assert rows.(
             "SELECT kind,payload FROM phoenix.rails_commands WHERE payload->>'user_id'=$1 ORDER BY id",
             [to_string(c.import.user_id)]
           ) == expected
  end
end
