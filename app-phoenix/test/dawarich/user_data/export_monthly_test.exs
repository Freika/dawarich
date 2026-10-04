defmodule Dawarich.UserData.ExportMonthlyTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Export.{Places, Points, Visits, Stats, Tracks, Digests}

  @monthly [
    {Points, "points"},
    {Visits, "visits"},
    {Stats, "stats"},
    {Tracks, "tracks"},
    {Digests, "digests"}
  ]

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    :ok
  end

  @tag :tmp_dir
  test "backup mixed-owner associations omit foreign names and coordinates", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)

    for {table, id} <- [{"imports", 988_101}, {"visits", 988_801}, {"places", 988_501}] do
      rows(
        "INSERT INTO #{table} SELECT (jsonb_populate_record(NULL::#{table},to_jsonb(t)||jsonb_build_object('id',id+100000,'user_id',988002,'name','foreign synthetic','latitude',63.123456,'longitude',24.654321,'lonlat','POINT(24.654321 63.123456)'))).* FROM #{table} t WHERE id=$1",
        [id]
      )
    end

    rows("UPDATE points SET import_id=1088101,visit_id=1088801 WHERE user_id=$1", [c.user_id])
    rows("UPDATE visits SET place_id=1088501 WHERE user_id=$1", [c.user_id])
    rows("UPDATE taggings SET taggable_id=1088501 WHERE tag_id=988701")
    expected = UserDataSeeds.entries("export_UTC")

    for {module, omitted} <- [
          {Points, ~w(import_reference visit_reference)},
          {Visits, ~w(place_reference)},
          {Dawarich.UserData.Export.Taggings,
           ~w(taggable_name taggable_latitude taggable_longitude)}
        ],
        entry <- module.write(ScratchRepo, c.user_id, dir, c.context) do
      bytes = File.read!(entry.path)
      refute bytes =~ "foreign synthetic"
      refute bytes =~ "63.123456"
      refute bytes =~ "24.654321"

      decode = fn bytes ->
        bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
      end

      wanted = Enum.map(decode.(expected[entry.name]), &Map.drop(&1, omitted))

      actual =
        Enum.map(
          decode.(bytes),
          &Map.reject(&1, fn {key, value} -> key in omitted and is_nil(value) end)
        )

      assert actual == wanted
    end
  end

  @tag :tmp_dir
  test "backup month boundaries references and JSON numbers match Rails", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)

    for zone <- ["UTC", "Europe/Berlin", "America/New_York"] do
      expected = UserDataSeeds.entries("export_" <> String.replace(zone, "/", "_"))
      manifest = Jason.decode!(expected["manifest.json"])
      context = %{c.context | zone: zone}
      [place] = Places.write(ScratchRepo, c.user_id, dir, context)
      assert File.read!(place.path) == expected["places.jsonl"]

      for {module, name} <- @monthly do
        entries = module.write(ScratchRepo, c.user_id, dir, context)
        assert Enum.map(entries, & &1.name) == manifest["files"][name], name <> " months"

        for entry <- entries do
          assert File.read!(entry.path) == expected[entry.name]
          assert entry.count == length(String.split(expected[entry.name], "\n", trim: true))
        end
      end
    end
  end

  @tag :tmp_dir
  test "backup streams rows without embedding points in export metadata", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)

    rows(
      "INSERT INTO points SELECT (jsonb_populate_record(NULL::points,to_jsonb(t)||jsonb_build_object('id',2000000+n,'timestamp',t.timestamp-n))).* FROM points t CROSS JOIN generate_series(1,5000) n WHERE t.id=988901"
    )

    rows(
      "INSERT INTO points SELECT (jsonb_populate_record(NULL::points,to_jsonb(t)||jsonb_build_object('id',3000000,'user_id',988002))).* FROM points t WHERE t.id=988901"
    )

    entries = Points.write(ScratchRepo, c.user_id, dir, c.context)
    assert Enum.sum(Enum.map(entries, & &1.count)) == 5003
    january = Enum.find(entries, &(&1.name == "points/2026/2026-01.jsonl"))
    assert january.count == 5001
    expected = UserDataSeeds.entries("export_UTC")[january.name]

    assert File.read!(january.path) ==
             expected <>
               Enum.map_join(
                 1..5000,
                 &String.replace(expected, "1769902200", Integer.to_string(1_769_902_200 - &1))
               )

    assert Map.keys(january) |> Enum.sort() == [:count, :name, :path]
    [point] = expected |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    assert point["visit_reference"]["name"] == "Synthetic visit"
    refute Map.has_key?(point, "id")
    refute Map.has_key?(point, "user_id")
  end
end
