defmodule Dawarich.Tracks.ReabsorberTest do
  use Dawarich.TracksCase

  import ExUnit.CaptureLog

  alias Dawarich.Tracks.Reabsorber

  @now 1_790_100_000
  @lookback @now - 21_600

  defp reabsorb_in_transaction(user) do
    with_log(fn ->
      ScratchRepo.transaction(fn ->
        claimed = Reabsorber.call(ScratchRepo, user, @now)
        %{rows: [[1]]} = ScratchRepo.query!("SELECT 1", [])
        claimed
      end)
    end)
  end

  test "a bounds collision rolls back to the savepoint and leaves the transaction usable" do
    user = user!()
    wide = track!(user.id, "device-c", @lookback - 100, @lookback + 100)
    track!(user.id, "device-c", @lookback - 90, @lookback - 10)
    point!(user.id, @lookback - 90, 12.3731, 51.3397, tracker_id: "device-c", track_id: wide)
    point!(user.id, @lookback - 10, 12.3741, 51.3407, tracker_id: "device-c", track_id: wide)
    orphan = point!(user.id, @lookback - 50, 12.3736, 51.3402, tracker_id: "device-c")
    point!(user.id, @lookback + 50, 12.4, 51.4, tracker_id: "device-other")
    before = track_rows()

    {result, log} = reabsorb_in_transaction(user)

    assert result == {:ok, 0}
    assert log =~ "event=tracks.reabsorb_orphan_points_failed reason=unique_violation"
    assert point_track_ids()[orphan] == nil
    assert track_rows() == before
    assert tracks_changed() == []
  end

  test "a track left with one point is invalid and rolls back to the savepoint" do
    user = user!()
    empty = track!(user.id, "device-i", @lookback - 100, @lookback + 100)
    orphan = point!(user.id, @lookback + 10, 12.3731, 51.3397, tracker_id: "device-i")
    before = track_rows()

    {result, log} = reabsorb_in_transaction(user)

    assert result == {:ok, 0}
    assert log =~ "reason=invalid user_id=#{user.id} track_id=#{empty}"
    assert point_track_ids()[orphan] == nil
    assert track_rows() == before
    assert tracks_changed() == []
  end
end
