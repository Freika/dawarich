defmodule Dawarich.Imports.OwntracksTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Owntracks
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)
  @columns ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)

  setup do
    Dawarich.Ingest.Sources.forget()
    :ok
  end

  test "owntracks recorder keeps location records and omits raw data" do
    for path <- Path.wildcard(Path.join(@dir, "owntracks_import_*.json")),
        Path.basename(path) != "owntracks_import_failure.json" do
      c = NormalFormats.seed!(Path.basename(path, ".json"), ScratchRepo)
      assert :ok = Owntracks.call(c.path, c.import, c.context)
      assert_snapshot(c)
    end
  end

  test "owntracks import preserves failed-batch notification text" do
    c = NormalFormats.seed!("owntracks_import_failure", ScratchRepo)
    assert :ok = Owntracks.call(c.path, c.import, c.context)
    assert_snapshot(c)
    assert length(c.expected["points"]) == 1001
    assert length(c.expected["notifications"]) == 1
  end

  defp assert_snapshot(c) do
    data = c.expected["import"]

    assert rows(
             "SELECT raw_points,doubles,processed,raw_data,status,error_message,source FROM imports WHERE id=$1",
             [c.import.id]
           ) ==
             [
               [
                 data["raw_points"],
                 data["doubles"],
                 data["processed"],
                 data["raw_data"],
                 0,
                 data["error_message"],
                 1
               ]
             ]

    select =
      Enum.map_join(@columns, ",", fn
        "lonlat" -> "ST_AsText(lonlat::geometry)"
        key when key in ~w(altitude_decimal course course_accuracy) -> key <> "::text"
        key -> key
      end)

    assert rows("SELECT #{select} FROM points WHERE import_id=$1 ORDER BY id", [c.import.id]) ==
             Enum.map(c.expected["points"], &Enum.map(@columns, fn key -> &1[key] end))

    assert rows(
             "SELECT title,content,CASE kind WHEN 2 THEN 'error' WHEN 1 THEN 'warning' ELSE 'info' END FROM notifications WHERE user_id=$1 ORDER BY id",
             [c.import.user_id]
           ) == c.expected["notifications"]

    fields =
      ~w(digest tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)

    assert rows(
             "SELECT #{Enum.join(fields, ",")} FROM point_sources WHERE id IN (SELECT source_id FROM points WHERE import_id=$1) ORDER BY digest",
             [c.import.id]
           ) ==
             Enum.map(c.expected["sources"], &Enum.map(fields, fn key -> &1[key] end))

    expected =
      Enum.map(c.expected["commands"], fn command ->
        payload = Map.put(command["payload"], "user_id", c.import.user_id)

        payload =
          if command["kind"] == "imports.progress",
            do: Map.put(payload, "import_id", c.import.id),
            else: payload

        [command["kind"], payload]
      end)

    assert rows(
             "SELECT kind,payload FROM phoenix.rails_commands WHERE payload->>'user_id'=$1 ORDER BY id",
             [to_string(c.import.user_id)]
           ) == expected
  end
end
