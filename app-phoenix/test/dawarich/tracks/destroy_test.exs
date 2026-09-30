defmodule Dawarich.Tracks.DestroyTest do
  use Dawarich.TracksCase, async: true, group: :tracks_db

  alias Dawarich.Tracks.Destroy

  defp shared_link!(resource_type, resource_id) do
    [[id]] =
      rows(
        "INSERT INTO shared_links (name, resource_type, resource_id, user_id, created_at, updated_at) " <>
          "VALUES ('link', $1, $2, 1, now(), now()) RETURNING id::text",
        [resource_type, resource_id]
      )

    id
  end

  defp identity(id) do
    [[tracker_id, start_at, end_at]] =
      rows(
        "SELECT tracker_id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint " <>
          "FROM tracks WHERE id = $1",
        [id]
      )

    %{"tracker_id" => tracker_id, "start_at" => start_at, "end_at" => end_at}
  end

  test "cascade matches destroy_all" do
    TracksFixtures.load!(ScratchRepo, "range_kept")

    [[track_id, start_at, end_at]] =
      rows(
        "SELECT id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint " <>
          "FROM tracks WHERE id = 2"
      )

    owned = for {id, ^track_id} <- point_track_ids(), do: id
    track_link = shared_link!(1, track_id)
    trip_link = shared_link!(0, track_id)

    assert Destroy.destroy!(ScratchRepo, 1, [track_id]) == [{track_id, start_at, end_at}]

    assert owned != []
    assert Enum.all?(owned, &(point_track_ids()[&1] == nil))
    assert rows("SELECT count(*) FROM track_segments WHERE track_id = $1", [track_id]) == [[0]]
    assert rows("SELECT id::text FROM shared_links ORDER BY resource_type") == [[trip_link]]
    refute track_link == trip_link
    assert rows("SELECT count(*) FROM tracks WHERE id = $1", [track_id]) == [[0]]

    assert tracks_changed() == [
             %{
               "user_id" => 1,
               "created" => [],
               "updated" => [],
               "destroyed" => [track_id],
               "min_ts" => start_at,
               "max_ts" => end_at
             }
           ]
  end

  test "clean_range spares kept tracks" do
    %{call: [call], expected: expected} = TracksFixtures.load!(ScratchRepo, "range_kept")
    identities = Map.new([1, 2, 3], &{&1, identity(&1)})
    owners = point_track_ids()

    rows = Destroy.clean_range!(ScratchRepo, 1, call["start_at"], call["end_at"])

    destroyed = for %{"action" => "destroyed", "track" => track} <- expected["events"], do: track
    assert Enum.map(rows, fn {id, _, _} -> identities[id] end) == destroyed
    assert rows("SELECT id FROM tracks ORDER BY id") == [[1], [2]]
    [{gone, _, _}] = rows

    for {point, track_id} <- owners do
      assert point_track_ids()[point] == if(track_id == gone, do: nil, else: track_id)
    end

    assert [%{"destroyed" => [^gone]}] = tracks_changed()
  end
end
