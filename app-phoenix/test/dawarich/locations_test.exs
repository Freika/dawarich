defmodule Dawarich.LocationsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.{Jsonb, Locations, RailsTime}

  @t0 1_700_000_000

  defp search(attrs \\ %{}) do
    Map.merge(
      %{
        lat: 52.52,
        lon: 13.405,
        limit: 50,
        radius: 500,
        date_from: nil,
        date_to: nil,
        name: "Cafe",
        address: ""
      },
      attrs
    )
  end

  defp point!(user_id, lat, lon, timestamp, attrs \\ %{}) do
    Repo.query!(
      """
      INSERT INTO points (user_id, timestamp, lonlat, accuracy, altitude, city, country, created_at, updated_at)
      VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5, $6, $7, $8, now(), now())
      """,
      [
        user_id,
        timestamp,
        lon,
        lat,
        attrs[:accuracy],
        attrs[:altitude],
        attrs[:city],
        attrs[:country]
      ]
    )
  end

  defp rows(zone, user_id, search),
    do: RailsTime.with_zone(zone, fn -> Locations.rows(user_id, search) end)

  defp index_conditions(node),
    do: List.wrap(node["Index Cond"]) ++ Enum.flat_map(node["Plans"] || [], &index_conditions/1)

  defp locations_plan(user_id, search) do
    {sql, args} = Locations.query(user_id, search)
    Repo.query!("ANALYZE points")
    Repo.query!("SET LOCAL enable_seqscan = off")
    [[[%{"Plan" => plan}]]] = Repo.query!("EXPLAIN (FORMAT JSON) #{sql}", args).rows
    plan
  end

  defp row(ts, accuracy, altitude, distance),
    do: [ts, 52.5 + ts / 1.0e9, 13.4, "C#{ts}", "D", altitude, accuracy, distance, "d#{ts}"]

  test "rows: the points scan takes both timestamp bounds as index conditions" do
    id = user!()
    start = 1_699_920_000
    search = search(%{date_from: ~D[2023-11-14], date_to: ~D[2023-11-14]})

    for {count, first, step} <- [{40_000, 1_000_000_000, 1}, {200, start, 60}] do
      Repo.query!(
        "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) " <>
          "SELECT $1, $2 + i * $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, now(), now() " <>
          "FROM generate_series(0, $6) AS i",
        [id, first, step, search.lon, search.lat, count - 1]
      )
    end

    conditions =
      "UTC"
      |> RailsTime.with_zone(fn -> locations_plan(id, search) end)
      |> index_conditions()
      |> Enum.join(" ")

    assert conditions =~ ~s("timestamp" >=)
    assert conditions =~ ~s("timestamp" < )
  end

  test "rows: date bounds include the first second and exclude the following midnight" do
    id = user!()
    start = 1_699_920_000
    finish = 1_700_006_400
    day = search(%{date_from: ~D[2023-11-14], date_to: ~D[2023-11-14]})

    point!(id, 52.52001, 13.40501, start - 1)
    point!(id, 52.52002, 13.40502, start)
    point!(id, 52.52003, 13.40503, finish - 1)
    point!(id, 52.52004, 13.40504, finish)

    assert "UTC" |> rows(id, day) |> Enum.map(&hd/1) |> Enum.sort() == [start, finish - 1]
  end

  test "rows: this user's points within the radius, Rails' zoned date, a NULL timestamp read as 0, date bounds at local midnight" do
    id = user!()
    other = user!()

    point!(id, 52.52001, 13.40502, @t0 + 7200, %{
      accuracy: 5,
      altitude: 42,
      city: "Berlin",
      country: "Germany"
    })

    point!(id, 52.52002, 13.40502, nil)
    point!(id, 52.5300, 13.4050, @t0)
    point!(other, 52.52001, 13.40502, @t0)

    assert [
             [ts, lat, lon, "Berlin", "Germany", 42, 5, distance, date],
             [0, _, _, nil, nil, nil, nil, _, epoch]
           ] =
             "Europe/Berlin" |> rows(id, search()) |> Enum.sort_by(&hd/1, :desc)

    assert {ts, lat, lon, date, epoch} ==
             {@t0 + 7200, 52.52001, 13.40502, "2023-11-15T01:13:20+01:00",
              "1970-01-01T01:00:00+01:00"}

    assert is_float(distance) and distance < 5

    day = search(%{date_from: ~D[2023-11-15], date_to: ~D[2023-11-15]})

    assert [[_, _, _, _, _, _, _, _, "2023-11-15T01:13:20+01:00"]] =
             rows("Europe/Berlin", id, day)

    assert rows("America/New_York", id, day) == []
    assert rows("Europe/Berlin", id, search(%{radius: 0})) == []
  end

  test "term: visits split after 30 minutes, newest first, Rails' duration text, the most accurate point, the averaged distance, the altitude range, the limit" do
    rows = [
      row(@t0, 20, 30, 1.004),
      row(@t0 + 600, 5, 42, 2.0),
      row(@t0 + 1200, nil, nil, 3.0),
      row(@t0 + 3001, nil, 35, 0.0),
      row(@t0 + 9000, 15, 30, 1.0),
      row(@t0 + 10_800, 15, 33, 1.0),
      row(@t0 + 12_600, 15, 31, 1.0),
      row(@t0 + 12_900, 15, 30, 1.0),
      row(@t0 + 20_000, 1, 1, 0.006),
      row(@t0 + 20_060, 1, 1, 0.0),
      row(@t0 + 30_000, 2, 7, 1.0),
      row(@t0 + 31_800, 2, 7, 1.0),
      row(@t0 + 33_600, 2, 7, 1.0)
    ]

    assert {:ok,
            {:object,
             [
               {"query", nil},
               {"locations", [location]},
               {"total_locations", 1},
               {"search_metadata", {:object, []}}
             ]}} =
             Locations.term(search(%{limit: 2}), Enum.shuffle(rows))

    {:object, fields} = location

    assert Enum.map(fields, &elem(&1, 0)) ==
             ~w(place_name coordinates address total_visits first_visit last_visit visits)

    assert {Jsonb.get(location, "place_name"), Jsonb.get(location, "coordinates"),
            Jsonb.get(location, "address"), Jsonb.get(location, "total_visits"),
            Jsonb.get(location, "first_visit"), Jsonb.get(location, "last_visit")} ==
             {"Cafe", [52.52, 13.405], "", 5, "d#{@t0 + 30_000}", "d#{@t0}"}

    assert [newest, minute] = Jsonb.get(location, "visits")

    assert {Jsonb.get(newest, "timestamp"), Jsonb.get(minute, "timestamp")} ==
             {@t0 + 30_000, @t0 + 20_000}

    assert Jsonb.get(minute, "distance_meters") == 0.01

    {:ok, {:object, [_, {"locations", [all]} | _]}} = Locations.term(search(), rows)
    visits = Jsonb.get(all, "visits")

    assert Enum.map(visits, &Jsonb.get(&1, "duration_estimate")) ==
             ["~1 hour", "~1 minute", "~1 hour 5 minutes", "~15 minutes", "~20 minutes"]

    [_, _, four, single, first] = visits
    {:object, keys} = four

    assert Enum.map(keys, &elem(&1, 0)) ==
             ~w(timestamp date coordinates distance_meters duration_estimate points_count accuracy_meters visit_details)

    details = Jsonb.get(four, "visit_details")
    {:object, detail_keys} = details

    assert Enum.map(detail_keys, &elem(&1, 0)) ==
             ~w(start_time end_time duration_minutes city country altitude_range)

    assert {Jsonb.get(four, "points_count"), Jsonb.get(four, "accuracy_meters"),
            Jsonb.get(details, "city"), Jsonb.get(details, "altitude_range"),
            Jsonb.get(details, "start_time"), Jsonb.get(details, "end_time")} ==
             {4, 15, "C#{@t0 + 9000}", "30m - 33m", "d#{@t0 + 9000}", "d#{@t0 + 12_900}"}

    assert {Jsonb.get(single, "accuracy_meters"), Jsonb.get(single, "distance_meters"),
            Jsonb.get(Jsonb.get(single, "visit_details"), "altitude_range")} == {nil, 0.0, "35m"}

    first_details = Jsonb.get(first, "visit_details")

    assert {Jsonb.get(first, "accuracy_meters"), Jsonb.get(first, "distance_meters"),
            Jsonb.get(first, "coordinates"), Jsonb.get(first_details, "altitude_range"),
            Jsonb.get(first_details, "duration_minutes")} ==
             {5, 2.0, [52.5 + (@t0 + 600) / 1.0e9, 13.4], "30m - 42m", 20}
  end

  test "term: nothing matched is an empty result; two matched points sharing a timestamp go to Rails" do
    assert Locations.term(search(), []) ==
             {:ok,
              {:object,
               [
                 {"query", nil},
                 {"locations", []},
                 {"total_locations", 0},
                 {"search_metadata", {:object, []}}
               ]}}

    same = [@t0, 52.5, 13.4, nil, nil, nil, nil, 1.0, "d"]

    assert {:replay, "matched points share a timestamp"} =
             Locations.term(search(), [same, List.replace_at(same, 1, 52.6)])
  end
end
