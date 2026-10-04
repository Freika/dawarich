defmodule Dawarich.Imports.KmzTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{ArchiveDispatch, ArchivePaths, Kml}
  alias Dawarich.Imports.Kml.Kmz
  alias Dawarich.Imports.GpxArchive.Error
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats/whole_create", __DIR__)

  test "kmz leaf chooses the Rails KML entry and cleans temporary files" do
    dir = Path.join(System.tmp_dir!(), "kmz-leaf-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    c = NormalFormats.seed!("kml_import_empty", ScratchRepo)
    wrapped = fixture("kmz_wrapped")
    inner = unwrap(wrapped, dir)
    context = Map.put(c.context, :temp_dir, dir)

    assert :ok =
             Kmz.with_kml(inner, context, fn path ->
               assert File.read!(path) == wrapped["kmz_leaf"]["bytes"]
               assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
               Kml.call(path, c.import, context)
             end)

    assert_points(wrapped["points"], c.import.id)
    assert File.ls!(dir) == [Path.basename(inner)]

    assert_raise RuntimeError, "callback failure", fn ->
      Kmz.with_kml(inner, context, fn _ -> raise "callback failure" end)
    end

    assert File.ls!(dir) == [Path.basename(inner)]
    File.rm!(inner)
    missing = fixture("kmz_missing_leaf")
    inner = unwrap(missing, dir)
    assert missing["parent"]["error_message"] =~ "No KML file found in KMZ archive"

    assert_raise Error, "No KML file found in KMZ archive", fn ->
      Kmz.with_kml(inner, context, fn _ -> flunk("missing leaf invoked callback") end)
    end

    assert File.ls!(dir) == [Path.basename(inner)]
    File.rm!(inner)
    assert File.ls!(dir) == []
  end

  defp fixture(name),
    do:
      @dir
      |> Path.join(name <> ".json")
      |> File.read!()
      |> Jason.decode!()
      |> NormalFormats.decode()

  defp unwrap(c, dir) do
    path = Path.join(@dir, c["input"])
    assert {:single_entry, entry} = ArchiveDispatch.inspect(path)
    inner = ArchivePaths.extract(path, entry, temp_dir: dir)
    assert File.read!(inner) == c["archive"]["bytes"]
    inner
  end

  defp assert_points(expected, id) do
    columns =
      ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)

    select =
      Enum.map_join(columns, ",", fn
        "lonlat" ->
          "ST_AsText(lonlat::geometry)"

        key when key in ~w(altitude_decimal course course_accuracy) ->
          "CASE WHEN #{key}=trunc(#{key}) THEN trunc(#{key})::text||'.0' ELSE trim_scale(#{key})::text END"

        key ->
          key
      end)

    assert ScratchRepo.query!("SELECT #{select} FROM points WHERE import_id=$1 ORDER BY id", [id]).rows ==
             Enum.map(expected, &Enum.map(columns, fn key -> &1[key] end))
  end
end
