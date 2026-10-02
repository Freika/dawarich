defmodule Dawarich.MapApi.ReadsTest do
  use Dawarich.IngestCase, async: false

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
