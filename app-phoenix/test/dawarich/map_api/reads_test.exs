defmodule Dawarich.MapApi.ReadsTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.MapApi
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @t0 1_735_689_600

  test "a clip whose pairs all repeat one position renders PostGIS' empty collection as Rails does" do
    user = owner()
    [track] = tracks!(user.id, 0..0)

    for offset <- [30, 31] do
      Repo.query!(
        "INSERT INTO points (user_id, track_id, timestamp, lonlat, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, 'SRID=4326;POINT(13.0005 52.0005)', now(), now())",
        [user.id, track, @t0 + offset]
      )
    end

    params = %{"id" => to_string(track), "start_at" => "#{@t0 + 30}", "end_at" => "#{@t0 + 31}"}

    assert {:ok, {:object, [_type, {"features", [{:object, feature}]}]}, [], 200} =
             MapApi.read(:track, user, params, DateTime.utc_now())

    {"geometry", geometry} = List.keyfind(feature, "geometry", 0)

    assert IO.iodata_to_binary(Ruby.json(geometry)) ==
             ~s({"type":"GeometryCollection","geometries":[]})
  end

  test "a page of tracks costs the same number of queries for 3 tracks as for 30" do
    user = owner()
    tracks!(user.id, 0..2)
    assert {three, 3} = counted(user)

    tracks!(user.id, 3..29)
    assert {thirty, 30} = counted(user)
    assert three > 0
    assert thirty == three
  end

  test "a slim page reads only the seven expressions Rails plucks" do
    user = owner()

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) " <>
        "VALUES ($1, #{@t0}, 'SRID=4326;POINT(13 52)', now(), now())",
      [user.id]
    )

    params = %{"slim" => "true", "end_at" => "1790856000"}
    {:points, term, _headers, _meta} = MapApi.read(:points, user, params, DateTime.utc_now())
    {queries, [_point]} = queries(term)

    assert [rows] = Enum.filter(queries, &String.contains?(&1, "ST_Y"))
    refute rows =~ "geodata"
    refute rows =~ "accuracy"
  end

  test "track lists omit segment geometry, while track detail retains coordinates and timeline" do
    user = owner()
    [id] = tracks!(user.id, 0..0)

    {list_queries, {:ok, list, _headers, 200}} =
      queries(fn ->
        MapApi.read(:tracks, user, %{}, DateTime.utc_now())
      end)

    [segment_sql] = Enum.filter(list_queries, &String.contains?(&1, "FROM track_segments"))
    refute segment_sql =~ "ST_DumpPoints"
    refute segment_sql =~ "s.path"
    refute segment_sql =~ "s.confidence"

    {detail_queries, {:ok, detail, _headers, 200}} =
      queries(fn ->
        MapApi.read(:track, user, %{"id" => to_string(id)}, DateTime.utc_now())
      end)

    [detail_sql] = Enum.filter(detail_queries, &String.contains?(&1, "FROM track_segments"))
    assert detail_sql =~ "ST_DumpPoints"
    [%{"properties" => list_properties}] = decode(list)["features"]
    [%{"properties" => detail_properties}] = decode(detail)["features"]
    assert list_properties["mode_timeline"] == detail_properties["mode_timeline"]
    assert length(list_properties["mode_timeline"]) == 2
    refute Map.has_key?(list_properties, "segments")

    assert Enum.map(detail_properties["segments"], & &1["coordinates"]) ==
             List.duplicate([[13.0, 52.0], [13.002, 52.002]], 2)
  end

  test "a warm points schema avoids repeated catalogue queries" do
    Dawarich.MapApi.PointRecord.invalidate()
    {cold, {:ok, columns}} = queries(&Dawarich.MapApi.PointRecord.columns/0)
    assert Enum.any?(cold, &String.contains?(&1, "pg_attribute"))
    {warm, {:ok, ^columns}} = queries(&Dawarich.MapApi.PointRecord.columns/0)
    refute Enum.any?(warm, &String.contains?(&1, "pg_attribute"))
  end

  test "a large page preserves ordering, coordinates and common fields in full and slim JSON" do
    user = owner()

    Repo.query!(
      """
      INSERT INTO points (user_id, timestamp, lonlat, velocity, created_at, updated_at)
      SELECT $1, $2::bigint + n, ST_SetSRID(ST_MakePoint(13 + n / 100000.0, 52.25), 4326)::geography,
             1.25, now(), now() FROM generate_series(1, 1000) n
      """,
      [user.id, @t0]
    )

    params = %{"per_page" => "1000", "order" => "asc", "end_at" => to_string(@t0 + 1000)}

    {:points, full, full_headers, full_meta} =
      MapApi.read(:points, user, params, DateTime.utc_now())

    {:points, slim, slim_headers, slim_meta} =
      MapApi.read(:points, user, Map.put(params, "slim", "true"), DateTime.utc_now())

    full_rows = decode(full.())
    slim_rows = decode(slim.())
    assert length(full_rows) == 1000
    assert length(slim_rows) == 1000
    assert full_headers == slim_headers
    assert full_meta.count == slim_meta.count
    assert Enum.map(full_rows, & &1["timestamp"]) == Enum.to_list((@t0 + 1)..(@t0 + 1000))

    for {full, slim} <- Enum.zip(full_rows, slim_rows) do
      assert Map.take(full, Map.keys(slim)) == slim
      assert full["revision"] == 0
      assert full["lonlat"] == "POINT (#{slim["longitude"]} #{slim["latitude"]})"
    end
  end

  defp decode(term), do: term |> Ruby.json() |> IO.iodata_to_binary() |> Jason.decode!()

  defp owner,
    do: %{id: user!(%{settings: %{"timezone" => "Europe/Berlin"}}), timezone: "Europe/Berlin"}

  defp tracks!(user_id, range) do
    for i <- range do
      [[id]] =
        Repo.query!(
          "INSERT INTO tracks (user_id, start_at, end_at, original_path, distance, avg_speed, duration, " <>
            "dominant_mode, created_at, updated_at) VALUES ($1, to_timestamp($2) AT TIME ZONE 'UTC', " <>
            "to_timestamp($2 + 300) AT TIME ZONE 'UTC', 'SRID=4326;LINESTRING(13 52,13.002 52.002)', 987, 11.25, " <>
            "300, 5, now(), now()) RETURNING id",
          [user_id, @t0 + i * 3600]
        ).rows

      for {from, to} <- [{0, 1}, {2, 3}] do
        Repo.query!(
          "INSERT INTO track_segments (track_id, transportation_mode, start_index, end_index, path, created_at, " <>
            "updated_at) VALUES ($1, 2, $2, $3, 'SRID=4326;LINESTRING(13 52,13.002 52.002)', now(), now())",
          [id, from, to]
        )
      end

      id
    end
  end

  defp counted(user) do
    {queries, {:ok, {:object, [_type, {"features", features}]}, _headers, 200}} =
      queries(fn -> MapApi.read(:tracks, user, %{}, DateTime.utc_now()) end)

    {length(queries), length(features)}
  end

  defp queries(fun) do
    handler = "map-api-reads-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == test_pid, do: send(test_pid, {:sql, meta.query})
      end,
      nil
    )

    try do
      result = fun.()
      {drain([]), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(acc) do
    receive do
      {:sql, sql} -> drain([sql | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
