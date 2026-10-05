defmodule Dawarich.Families.HistoryTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Families.History

  @now ~U[2030-01-15 10:30:00.000000Z]
  @share %{
    "enabled" => true,
    "share_history" => true,
    "history_before_sharing" => true,
    "history_window" => "all"
  }

  test "locations and history exclude each sharing viewer like Rails 1.15.3" do
    {owner, member, start} = seed_member_points!()

    Repo.query!("UPDATE users SET settings = $2 WHERE id = $1", [
      owner,
      %{"timezone" => "UTC", "family" => %{"location_sharing" => @share}}
    ])

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) " <>
        "VALUES ($1, $2, ST_SetSRID(ST_MakePoint(13.4, 52.5), 4326), now(), now())",
      [owner, start]
    )

    params = %{"start_at" => "2030-01-01T00:00:00Z", "end_at" => "2030-01-15T10:30:00Z"}

    for {viewer, other} <- [{owner, member}, {member, owner}] do
      user = %{id: viewer, timezone: "UTC"}
      assert {:ok, 200, {:object, locations}} = Dawarich.Families.Locations.read(user, @now)
      assert [{:object, location}] = Map.new(locations)["locations"]
      assert Map.new(location)["user_id"] == other
      assert Map.new(locations)["sharing_enabled"] == true

      assert {:ok, 200, {:object, [{"members", [{:object, history}]}]}} =
               History.read(user, params, @now)

      assert Map.new(history)["user_id"] == other
      assert Map.new(history)["points"] != []
    end
  end

  test "more than 5000 points keep every ceil(total / 5000)th row in timestamp order" do
    {owner, _member, start} = seed_member_points!()
    params = %{"start_at" => "2030-01-01T00:00:00Z", "end_at" => "2030-01-15T10:30:00Z"}

    assert {:ok, 200, {:object, [{"members", [{:object, fields}]}]}} =
             History.read(%{id: owner, timezone: "UTC"}, params, @now)

    stamps = for [_lat, _lon, stamp] <- Map.new(fields)["points"], do: stamp
    assert stamps == Enum.map(0..5002//2, &(start + &1))
  end

  test "the points scan takes both timestamp bounds as index conditions" do
    {_owner, member, _start} = seed_member_points!()
    Repo.query!("ANALYZE points")
    Repo.query!("SET LOCAL enable_seqscan = off")

    params = [member, "2030-01-15T09:00:00Z", "2030-01-15T09:05:00Z", @now, "1 year", nil, true]

    [[[%{"Plan" => plan}]]] =
      Repo.query!("EXPLAIN (FORMAT JSON) " <> History.points_sql(), params).rows

    conditions = plan |> index_conditions() |> Enum.join(" ")
    assert conditions =~ ~s("timestamp" >=)
    assert conditions =~ ~s("timestamp" <=)
  end

  defp index_conditions(%{"Plans" => plans} = node),
    do: List.wrap(node["Index Cond"]) ++ Enum.flat_map(plans, &index_conditions/1)

  defp index_conditions(node), do: List.wrap(node["Index Cond"])

  defp seed_member_points! do
    owner = user!(%{settings: %{"timezone" => "UTC"}})
    member = user!(%{settings: %{"family" => %{"location_sharing" => @share}}})

    [[family]] =
      Repo.query!(
        "INSERT INTO families (name, creator_id, created_at, updated_at) VALUES ('f', $1, now(), now()) RETURNING id",
        [owner]
      ).rows

    for {id, role} <- [{owner, 0}, {member, 1}] do
      Repo.query!(
        "INSERT INTO family_memberships (family_id, user_id, role, created_at, updated_at) VALUES ($1, $2, $3, now(), now())",
        [family, id, role]
      )
    end

    start = DateTime.to_unix(@now) - 6000

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) " <>
        "SELECT $1, $2 + i, ST_SetSRID(ST_MakePoint(12.37, 51.34), 4326), now(), now() " <>
        "FROM generate_series(0, 5002) AS i",
      [member, start]
    )

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) " <>
        "SELECT $1, 1000000000 + i, ST_SetSRID(ST_MakePoint(12.37, 51.34), 4326), now(), now() " <>
        "FROM generate_series(0, 39999) AS i",
      [member]
    )

    {owner, member, start}
  end
end
