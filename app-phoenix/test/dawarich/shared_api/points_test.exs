defmodule Dawarich.SharedApi.PointsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.SharedApi.Points

  @fixture Path.expand("../../fixtures/api_shared/golden.json", __DIR__)

  test "trip and track points obey resource relation and owner boundaries" do
    link = seed!("points_trip_edges")
    assert {:ok, rows} = Points.index(link)
    assert Enum.map(rows, &List.last/1) == [1_774_742_400, 1_774_746_000]
    assert Points.index(%{link | user_id: 951_002}) == {:ok, []}
    assert Points.index(%{link | resource_id: 959_999}) == {:ok, []}
    Repo.query!("DELETE FROM points")

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, track_id, anomaly, lonlat, created_at, updated_at) VALUES ($1, 1, 951201, true, ST_SetSRID(ST_MakePoint(13,52),4326)::geography, NOW(), NOW()), ($1, 2, 951202, false, ST_SetSRID(ST_MakePoint(13,52),4326)::geography, NOW(), NOW())",
      [link.user_id]
    )

    track = %{link | type: "track", resource_id: 951_201}
    assert Points.index(track) == {:ok, [[13.0, 52.0, 1]]}
    assert Points.index(%{track | resource_id: 951_202}) == {:ok, []}
    assert Points.index(%{track | resource_id: 959_999}) == {:ok, []}
  end

  test "privacy exclusion happens before SQL stride sampling" do
    link = seed!("points_privacy_before_stride")
    assert {:ok, rows} = Points.index(link)
    assert length(rows) == 10_000
    assert Enum.all?(rows, fn [lon, lat, _] -> abs(lon - 13.405) < 1.0e-12 and lat == 52.52 end)
    assert List.last(hd(rows)) == 1_774_742_401
  end

  test "10001 points use ceil stride rather than truncation" do
    link = seed!("points_10001")
    assert {:ok, rows} = Points.index(link)
    assert length(rows) == 5001

    assert Enum.take(Enum.map(rows, &List.last/1), 3) == [
             1_774_742_400,
             1_774_742_402,
             1_774_742_404
           ]

    assert List.last(List.last(rows)) == 1_774_752_400
    Repo.query!("DELETE FROM points WHERE timestamp = $1", [1_774_752_400])
    assert {:ok, full} = Points.index(link)
    assert length(full) == 10_000

    Repo.query!(
      "UPDATE points SET timestamp = $1, lonlat = ST_SetSRID(ST_MakePoint(14,52),4326)::geography WHERE timestamp = $2",
      [1_774_742_400, 1_774_742_401]
    )

    assert {:replay, _} = Points.index(link)
  end

  test "timeline includes owner's whole final local day across DST" do
    link = seed!("points_timeline_dst")
    assert {:ok, rows} = Points.index(link)
    assert Enum.map(rows, &List.last/1) == [1_774_738_800, 1_774_821_599]

    assert {:replay, _} =
             Points.index(%{
               link
               | settings: %{"start_date" => "invalid", "end_date" => "2026-03-29"}
             })
  end

  defp seed!(name) do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    kase = Enum.find(fixture["cases"], &(&1["name"] == name))

    for [table, rows] <- fixture["setups"][kase["setup"]], rows != [] do
      Repo.query!(
        "INSERT INTO #{table} SELECT * FROM json_populate_recordset(NULL::#{table}, $1::text::json)",
        [Jason.encode!(rows)]
      )
    end

    [row] =
      fixture["setups"][kase["setup"]]
      |> Map.new(fn [table, rows] -> {table, rows} end)
      |> Map.fetch!("shared_links")

    %{
      type: Enum.at(~w(trip track timeline live), row["resource_type"]),
      user_id: row["user_id"],
      resource_id: row["resource_id"],
      settings: row["settings"],
      created_at: NaiveDateTime.from_iso8601!(row["created_at"])
    }
  end
end
