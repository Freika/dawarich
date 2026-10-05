defmodule Dawarich.UserData.RestoreMonthlyTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore.{Areas, Places, Visits, Tracks, Stats, Digests, Monthly}

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("v2", ScratchRepo)
    entries = UserDataSeeds.entries("export_UTC")

    data =
      Map.new(~w(areas places visits tracks stats digests), fn name ->
        path =
          if name in ~w(areas places), do: name <> ".jsonl", else: name <> "/2026/2026-01.jsonl"

        {name, entries[path] |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)}
      end)

    %{c: c, data: data, entries: entries}
  end

  @tag :tmp_dir
  test "restore monthly and root fallback entities reconstruct relationships", %{
    c: c,
    data: data,
    tmp_dir: dir
  } do
    assert Areas.call(ScratchRepo, c.user_id, data["areas"], c.context) == 1
    assert Places.call(ScratchRepo, c.user_id, data["places"], c.context) == 1

    for {module, name} <- [
          {Visits, "visits"},
          {Tracks, "tracks"},
          {Stats, "stats"},
          {Digests, "digests"}
        ] do
      File.write!(
        Path.join(dir, name <> ".jsonl"),
        Enum.map_join(data[name], "", &(Jason.encode!(&1) <> "\n"))
      )

      assert Monthly.call(
               module,
               ScratchRepo,
               c.user_id,
               dir,
               %{"files" => %{name => []}},
               name,
               c.context
             ) == c.expected["result"][name <> "_created"]
    end

    assert [["Synthetic visit", hd(data["places"])["name"], c.user_id]] ==
             rows("SELECT v.name,p.name,v.user_id FROM visits v JOIN places p ON p.id=v.place_id")

    assert [["LINESTRING(12.4 51.3,12.5 51.4)", 1250, 1, c.user_id]] ==
             rows("SELECT ST_AsText(original_path),distance,dominant_mode,user_id FROM tracks")

    assert [[2, 0, 1, 1250]] ==
             rows("SELECT transportation_mode,start_index,end_index,distance FROM track_segments")

    assert [[2026, 1, 1250, [[31, 1.25]], []]] ==
             rows("SELECT year,month,distance,daily_distance,toponyms FROM stats")

    assert [[2026, 1, 0, 1250, %{"31" => 1250}]] ==
             rows("SELECT year,month,period_type,distance,monthly_distances FROM digests")

    for table <- ~w(stats digests) do
      [[uuid]] = rows("SELECT sharing_uuid::text FROM #{table}")
      refute uuid == hd(data[table])["sharing_uuid"]
    end

    for {module, name} <- [
          {Dawarich.UserData.Export.Visits, "visits"},
          {Dawarich.UserData.Export.Tracks, "tracks"},
          {Dawarich.UserData.Export.Stats, "stats"},
          {Dawarich.UserData.Export.Digests, "digests"}
        ] do
      [entry] = module.write(ScratchRepo, c.user_id, dir, c.context)

      actual =
        entry.path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      expected = data[name]

      normalize = fn row ->
        if name in ~w(stats digests), do: Map.put(row, "sharing_uuid", "generated"), else: row
      end

      assert Enum.map(actual, normalize) == Enum.map(expected, normalize)
    end

    visit = hd(data["visits"])

    fresh =
      visit
      |> Map.put("name", "created missing place")
      |> Map.put("started_at", "2026-02-02T00:00:00Z")
      |> Map.put("ended_at", "2026-02-02T00:30:00Z")
      |> Map.put("place_reference", %{
        "name" => "new place",
        "latitude" => "40",
        "longitude" => "10",
        "source" => "manual"
      })

    assert Visits.call(ScratchRepo, c.user_id, [fresh], c.context) == 1

    assert [["new place"]] ==
             rows(
               "SELECT p.name FROM visits v JOIN places p ON p.id=v.place_id WHERE v.name='created missing place'"
             )

    nearby =
      fresh
      |> Map.put("name", "nearby")
      |> Map.put("started_at", "2026-02-03T00:00:00Z")
      |> Map.put("ended_at", "2026-02-03T00:30:00Z")
      |> Map.put("place_reference", %{
        "name" => "different",
        "latitude" => 40.00001,
        "longitude" => 10.00001
      })

    assert Visits.call(ScratchRepo, c.user_id, [nearby], c.context) == 1

    assert [["new place"]] ==
             rows(
               "SELECT p.name FROM visits v JOIN places p ON p.id=v.place_id WHERE v.name='nearby'"
             )

    File.mkdir_p!(Path.join(dir, "stats"))

    for {file, distance} <- [{"b", 20}, {"a", 10}] do
      row = hd(data["stats"]) |> Map.put("month", 2) |> Map.put("distance", distance)
      File.write!(Path.join(dir, "stats/#{file}.jsonl"), Jason.encode!(row) <> "\n")
    end

    manifest = %{
      "files" => %{"stats" => ["stats/b.jsonl", "../unsafe.jsonl", "absent", "stats/a.jsonl"]}
    }

    assert Monthly.call(Stats, ScratchRepo, c.user_id, dir, manifest, "stats", c.context) == 1
    assert [[10]] == rows("SELECT distance FROM stats WHERE month=2")
    assert [] == rows("SELECT command_type FROM job_outbox")
  end

  test "restore existing records preserve Rails duplicate and current-column rules", %{
    c: c,
    data: data
  } do
    for {module, name} <- [
          {Visits, "visits"},
          {Tracks, "tracks"},
          {Stats, "stats"},
          {Digests, "digests"}
        ] do
      assert module.call(ScratchRepo, c.user_id, data[name], c.context) == 1
      assert module.call(ScratchRepo, c.user_id, data[name], c.context) == 0
      assert module.call(ScratchRepo, c.user_id, nil, c.context) == 0
    end

    stat = hd(data["stats"]) |> Map.put("distance", 999)
    assert Stats.call(ScratchRepo, c.user_id, [stat], c.context) == 0
    assert [[1250]] == rows("SELECT distance FROM stats")

    assert Stats.call(
             ScratchRepo,
             c.user_id,
             [%{stat | "month" => 2} |> Map.put("dropped_column", true)],
             c.context
           ) == 0

    assert Stats.call(
             ScratchRepo,
             c.user_id,
             [nil, %{}, %{stat | "month" => 0}, %{stat | "month" => 1.5}],
             c.context
           ) == 0

    assert Stats.call(ScratchRepo, c.user_id, [%{stat | "month" => "08"}], c.context) == 1

    track =
      hd(data["tracks"])
      |> Map.put("distance", 999)
      |> Map.put("user_id", 123)
      |> Map.put("id", 999_999)
      |> Map.put("dropped_column", true)

    assert Tracks.call(ScratchRepo, c.user_id, [track], c.context) == 0
    assert [[999, c.user_id]] == rows("SELECT distance,user_id FROM tracks")
    assert [[1]] == rows("SELECT count(*) FROM track_segments")

    assert Tracks.call(
             ScratchRepo,
             c.user_id,
             [
               %{track | "start_at" => "2026-03-01T00:00:00Z", "end_at" => "2026-03-01T00:30:00Z"}
             ],
             c.context
           ) == 1

    assert [[0]] == rows("SELECT count(*) FROM tracks WHERE id=999999 OR user_id=123")

    assert Digests.call(
             ScratchRepo,
             c.user_id,
             [nil, %{}, %{hd(data["digests"]) | "month" => 13}],
             c.context
           ) == 0

    assert Visits.call(
             ScratchRepo,
             c.user_id,
             [nil, %{}, %{hd(data["visits"]) | "duration" => nil}],
             c.context
           ) == 0

    assert [[1]] == rows("SELECT count(*) FROM visits")
    stopped = Map.put(c.context, :fence, fn _ -> raise Dawarich.Imports.LeaseLost end)

    for {module, name} <- [
          {Visits, "visits"},
          {Tracks, "tracks"},
          {Stats, "stats"},
          {Digests, "digests"}
        ] do
      row =
        hd(data[name])
        |> Map.merge(%{
          "name" => "fenced",
          "year" => 2027,
          "started_at" => "2027-01-01T00:00:00Z",
          "ended_at" => "2027-01-01T00:30:00Z",
          "start_at" => "2027-01-01T00:00:00Z",
          "end_at" => "2027-01-01T00:30:00Z"
        })

      row =
        case name do
          "visits" -> Map.drop(row, ~w(year start_at end_at))
          "tracks" -> Map.drop(row, ~w(name year started_at ended_at))
          _ -> Map.drop(row, ~w(name start_at end_at started_at ended_at))
        end

      assert_raise Dawarich.Imports.LeaseLost, fn ->
        module.call(ScratchRepo, c.user_id, [row], stopped)
      end
    end
  end
end
