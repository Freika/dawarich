defmodule Dawarich.ReleaseOperations.TracksDedupTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.ReleaseOperations.TracksDedup
  alias Dawarich.Wave6Fixtures

  setup do: Wave6Fixtures.reset!()

  test "keeps the newest track per start and end, detaches the losers' points and deletes their segments" do
    user = Wave6Fixtures.user!()
    bounds = %{"start_at" => ~N[2020-05-01 10:00:00], "end_at" => ~N[2020-05-01 11:00:00]}
    loser = Wave6Fixtures.track!(user, Map.put(bounds, "tracker_id", "phone"))
    winner = Wave6Fixtures.track!(user, Map.put(bounds, "tracker_id", "watch"))
    unique = Wave6Fixtures.track!(user)
    loser_point = Wave6Fixtures.point!(user, %{"track_id" => loser})
    winner_point = Wave6Fixtures.point!(user, %{"track_id" => winner})
    Wave6Fixtures.segment!(loser)
    winner_segment = Wave6Fixtures.segment!(winner)
    unique_segment = Wave6Fixtures.segment!(unique)

    assert TracksDedup.perform(%Oban.Job{args: %{"version" => 1, "user_id" => user}}) == :ok

    assert rows("SELECT id FROM tracks ORDER BY id") == [[winner], [unique]]

    assert rows("SELECT id FROM track_segments ORDER BY id") == [
             [winner_segment],
             [unique_segment]
           ]

    assert rows("SELECT id, track_id FROM points ORDER BY id") == [
             [loser_point, nil],
             [winner_point, winner]
           ]
  end

  test "a deleted user is skipped" do
    user = Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})
    bounds = %{"start_at" => ~N[2020-05-01 10:00:00], "end_at" => ~N[2020-05-01 11:00:00]}
    first = Wave6Fixtures.track!(user, Map.put(bounds, "tracker_id", "phone"))
    second = Wave6Fixtures.track!(user, Map.put(bounds, "tracker_id", "watch"))

    assert TracksDedup.run(ScratchRepo, user) == :ok

    assert rows("SELECT id FROM tracks ORDER BY id") == [[first], [second]]
  end

  test "decodes version 1 payloads exactly" do
    assert TracksDedup.args_from_command(1, %{"user_id" => 1}) ==
             {:ok, %{"version" => 1, "user_id" => 1}}

    for invalid <- [%{}, %{"user_id" => "1"}, %{"user_id" => 1, "extra" => 1}] do
      assert TracksDedup.args_from_command(1, invalid) == {:error, "invalid_payload"}
    end

    assert TracksDedup.args_from_command(2, %{"user_id" => 1}) == {:error, "unsupported_version"}

    assert TracksDedup.perform(%Oban.Job{args: %{"version" => 2, "user_id" => 1}}) ==
             {:cancel, :unsupported_version}
  end
end
