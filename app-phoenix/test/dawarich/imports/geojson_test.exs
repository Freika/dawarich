defmodule Dawarich.Imports.GeojsonTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Geojson
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)
  @columns ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)

  setup do
    Dawarich.Ingest.Sources.forget()
    :ok
  end

  test "geojson timeless points produce the Rails warning after commit" do
    for path <- Path.wildcard(Path.join(@dir, "geojson_import_*.json")),
        Path.basename(path) not in ~w(geojson_import_failure.json geojson_import_malformed.json) do
      c = NormalFormats.seed!(Path.basename(path, ".json"), ScratchRepo)

      ScratchRepo.query!("UPDATE imports SET name=$2 WHERE id=$1", [
        c.import.id,
        c.expected["input"]
      ])

      if c.expected["legacy"] do
        assert {:error, :legacy_checked} =
                 ScratchRepo.transaction(fn ->
                   ScratchRepo.query!(
                     "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                   )

                   Dawarich.Ingest.Sources.forget()

                   assert :ok =
                            Geojson.call(c.path, c.import, %{c.context | altitude_decimal?: false})

                   assert_snapshot(c)
                   ScratchRepo.rollback(:legacy_checked)
                 end)

        Dawarich.Ingest.Sources.forget()
      else
        assert :ok = Geojson.call(c.path, c.import, c.context)
        assert_snapshot(c)
      end
    end
  end

  test "geojson validation and a late DB error leave no point effects" do
    for name <- ~w(geojson_import_failure geojson_import_malformed) do
      c = NormalFormats.seed!(name, ScratchRepo)

      exception =
        if name == "geojson_import_failure",
          do: Postgrex.Error,
          else: Dawarich.Imports.JsonStream.Error

      error = assert_raise exception, fn -> Geojson.call(c.path, c.import, c.context) end

      if exception == Postgrex.Error do
        assert Dawarich.Imports.NormalBatchErrors.message(error) == c.expected["error"]["message"]
      end

      assert_snapshot(c)
      assert c.expected["points"] == []
      assert c.expected["notifications"] == []
    end
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
                 6
               ]
             ]

    columns = if c.expected["legacy"], do: @columns -- ["altitude_decimal"], else: @columns

    select =
      Enum.map_join(columns, ",", fn
        "lonlat" -> "ST_AsText(lonlat::geometry)"
        key when key in ~w(altitude_decimal course course_accuracy) -> "trim_scale(#{key})::text"
        key -> key
      end)

    assert rows("SELECT #{select} FROM points WHERE import_id=$1 ORDER BY id", [c.import.id]) ==
             Enum.map(c.expected["points"], &Enum.map(columns, fn key -> &1[key] end))

    assert rows(
             "SELECT title,content,CASE kind WHEN 2 THEN 'error' WHEN 1 THEN 'warning' ELSE 'info' END FROM notifications WHERE user_id=$1 ORDER BY id",
             [c.import.user_id]
           ) == c.expected["notifications"]

    fields =
      ~w(digest tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)

    unless c.expected["legacy"] do
      assert rows(
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

    assert rows(
             "SELECT kind,payload FROM phoenix.rails_commands WHERE payload->>'user_id'=$1 ORDER BY id",
             [to_string(c.import.user_id)]
           ) == expected
  end
end
