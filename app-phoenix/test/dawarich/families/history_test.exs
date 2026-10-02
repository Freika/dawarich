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

  test "more than 5000 points keep every ceil(total / 5000)th row in timestamp order" do
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

    params = %{"start_at" => "2030-01-01T00:00:00Z", "end_at" => "2030-01-15T10:30:00Z"}

    assert {:ok, 200, {:object, [{"members", [{:object, fields}]}]}} =
             History.read(%{id: owner, timezone: "UTC"}, params, @now)

    stamps = for [_lat, _lon, stamp] <- Map.new(fields)["points"], do: stamp
    assert stamps == Enum.map(0..5002//2, &(start + &1))
  end
end
