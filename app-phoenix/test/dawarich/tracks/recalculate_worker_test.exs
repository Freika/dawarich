defmodule Dawarich.Tracks.RecalculateWorkerTest do
  use Dawarich.TracksCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.Tracks.RecalculateWorker

  defp run(track_id),
    do:
      RecalculateWorker.run(ScratchRepo, oban(), %{
        "track_id" => track_id,
        "event_id" => Ecto.UUID.generate()
      })

  test "reproduces RecalculateJob" do
    %{call: calls, expected: expected} = TracksFixtures.load!(ScratchRepo, "recalculate")
    known = identities()
    before = rows("SELECT id, lock_version, updated_at FROM tracks ORDER BY id")

    for %{"track_id" => id} <- calls, do: assert(run(id) == :ok)

    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert rows("SELECT count(*) FROM track_segments") == [[length(expected["track_segments"])]]
    assert events(known) == expected_events(expected)

    [[1, 0, changed_at], [2, 0, unchanged_at], [3, 0, _]] = before

    assert [[1, 1, changed_after], [2, 0, ^unchanged_at]] =
             rows("SELECT id, lock_version, updated_at FROM tracks ORDER BY id")

    assert NaiveDateTime.compare(changed_after, changed_at) == :gt
  end

  test "a track left without two usable points is reported, not raised" do
    user = user!()
    track = track!(user.id, "device-a", 1_790_000_000, 1_790_000_060)

    for {ts, anomaly} <- [{1_790_000_000, true}, {1_790_000_060, false}] do
      id = point!(user.id, ts, 12.3731, 51.3397, track_id: track)
      rows("UPDATE points SET anomaly = $1 WHERE id = $2", [anomaly, id])
    end

    before = track_rows()

    log = capture_log(fn -> assert run(track) == :ok end)

    assert log =~ "Failed to recalculate track #{track}"
    assert track_rows() == before
    assert tracks_changed() == []
  end

  test "a missing track is left alone" do
    assert capture_log(fn -> assert run(424_242) == :ok end) =~ "Track 424242 not found"
    assert tracks_changed() == []
  end

  test "decodes version 1 payloads exactly" do
    assert RecalculateWorker.args_from_command(1, %{"track_id" => 7}) == {:ok, %{"track_id" => 7}}

    for bad <- [%{"track_id" => "7"}, %{"track_id" => 7, "extra" => 1}, %{}],
        do: assert(RecalculateWorker.args_from_command(1, bad) == {:error, "invalid_payload"})

    assert RecalculateWorker.args_from_command(2, %{"track_id" => 7}) ==
             {:error, "unsupported_version"}
  end
end
