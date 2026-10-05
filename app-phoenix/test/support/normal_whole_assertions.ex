defmodule Dawarich.Test.NormalWholeAssertions do
  @moduledoc false
  import ExUnit.Assertions
  alias Dawarich.Test.NormalWholeEffects

  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)
  @statuses ~w(created processing completed failed deleting)
  @extraction ~w(not_attempted pending running completed failed unsupported)
  @parent ~w(id name source raw_points doubles processed raw_data status error_message additional_data_extraction_status additional_data_extraction processing_started_at)
  @point ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)
  @dimension ~w(digest tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)

  def assert_contract(c, repo, owner \\ :sidekiq) do
    rows = fn sql, args -> repo.query!(sql, args, log: false).rows end

    if parent = c.expected["parent"] do
      assert_import(c, repo, parent)
      assert parent["source"] == c.expected["source_transition"]
    else
      assert [] == rows.("SELECT id FROM imports WHERE id=$1", [c.import.id])
    end

    assert Enum.map(c.expected["children"], & &1["id"]) ==
             rows.(
               "SELECT id FROM imports WHERE user_id=$1 AND id<>$2 ORDER BY id",
               [c.import.user_id, c.import.id]
             )
             |> List.flatten()

    for child <- c.expected["children"], do: assert_import(c, repo, child)

    select =
      Enum.map_join(@point, ",", fn
        "lonlat" ->
          "ST_AsText(lonlat::geometry)"

        key when key in ~w(altitude_decimal course course_accuracy) ->
          "CASE WHEN #{key}=trunc(#{key}) THEN trunc(#{key})::text||'.0' ELSE trim_scale(#{key})::text END"

        key ->
          key
      end)

    assert Enum.map(c.expected["points"], fn point ->
             [c.import.user_id, c.import.id | Enum.map(@point, &point[&1])]
           end) ==
             rows.(
               "SELECT user_id,import_id,#{select} FROM points WHERE import_id=$1 ORDER BY id",
               [c.import.id]
             )

    assert Enum.map(c.expected["sources"], fn source -> Enum.map(@dimension, &source[&1]) end) ==
             rows.(
               "SELECT #{Enum.join(@dimension, ",")} FROM point_sources WHERE id IN (SELECT source_id FROM points WHERE import_id=$1) ORDER BY digest",
               [c.import.id]
             )

    actual =
      rows.(
        "SELECT title,content,CASE kind WHEN 2 THEN 'error' WHEN 1 THEN 'warning' ELSE 'info' END FROM notifications WHERE user_id=$1 ORDER BY id",
        [c.import.user_id]
      )

    assert Enum.map(c.expected["notifications"], &notification/1) ==
             Enum.map(actual, &notification/1)

    assert NormalWholeEffects.expected(c, owner) ==
             rows.(
               "SELECT kind,payload FROM (SELECT created_at,id AS position,kind,payload FROM phoenix.rails_commands UNION ALL SELECT created_at,aggregate_id,'native.command',jsonb_build_object('command_type',command_type,'command_payload',payload) FROM job_outbox) effects ORDER BY created_at,position",
               []
             )
             |> Enum.map(fn
               ["native.command", payload] ->
                 ["command", payload]

               ["imports.postprocessing_step", %{"step" => "command"} = payload] ->
                 ["command", Map.take(payload, ["command_type", "command_payload"])]

               row ->
                 row
             end)

    NormalWholeEffects.assert_routes(c, repo, owner)
  end

  defp assert_import(c, repo, expected) do
    values =
      Enum.map(@parent, fn
        "source" ->
          Enum.find_index(@sources, &(&1 == expected["source"]))

        "status" ->
          Enum.find_index(@statuses, &(&1 == expected["status"]))

        "additional_data_extraction_status" ->
          Enum.find_index(@extraction, &(&1 == expected["additional_data_extraction_status"]))

        "processing_started_at" ->
          timestamp(expected["processing_started_at"])

        key ->
          expected[key]
      end)

    assert [values ++ [c.import.user_id]] ==
             repo.query!(
               "SELECT #{Enum.join(@parent, ",")},user_id FROM imports WHERE id=$1",
               [expected["id"]],
               log: false
             ).rows

    attachments =
      repo.query!(
        "SELECT b.key,b.filename,b.content_type FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1 ORDER BY a.id",
        [expected["id"]],
        log: false
      ).rows

    case expected["file"] do
      nil ->
        assert attachments == []

      file ->
        assert [[key, filename, type]] = attachments

        assert [file["filename"], file["content_type"], file["bytes"]] ==
                 [filename, type, File.read!(Dawarich.Storage.disk_path(c.root, key))]
    end
  end

  defp timestamp(nil), do: nil

  defp timestamp(value) do
    value = String.replace(value, " ", "T", global: false)
    value = Regex.replace(~r/ ([+-]\d{2})(\d{2})$/, value, "\\1:\\2")
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    naive = DateTime.to_naive(datetime)
    {microseconds, _} = naive.microsecond
    %{naive | microsecond: {microseconds, 6}}
  end

  defp notification([title, content, kind]) do
    content = Regex.replace(~r/((?:Stacktrace|Backtrace): ).*$/is, content, "\\1<backend frames>")
    [title, content, kind]
  end
end
