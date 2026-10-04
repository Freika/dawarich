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
