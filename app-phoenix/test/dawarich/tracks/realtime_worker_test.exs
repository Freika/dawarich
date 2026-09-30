defmodule Dawarich.Tracks.RealtimeWorkerTest do
  use Dawarich.TracksCase, async: true, group: :scratch_db

  alias Dawarich.Tracks.{PerUserLock, RealtimeWorker}

  defp commands,
    do:
      rows(
        "SELECT kind, payload FROM phoenix.rails_commands WHERE kind <> 'tracks_changed' ORDER BY id"
      )

  defp run(user_id, opts),
    do:
      RealtimeWorker.run(
        ScratchRepo,
        oban(),
        %{"user_id" => user_id, "event_id" => Ecto.UUID.generate()},
        opts
      )

  test "a second insert while the first is still available dedupes to one queued job at priority 0" do
    user = user!()

    assert {:ok, first} = Oban.insert(oban(), RealtimeWorker.new(%{"user_id" => user.id}))
    assert {:ok, second} = Oban.insert(oban(), RealtimeWorker.new(%{"user_id" => user.id}))

    assert first.id == second.id

    assert rows("SELECT count(*), max(priority) FROM oban.oban_jobs WHERE worker = $1", [
             inspect(RealtimeWorker)
           ]) == [[1, 0]]
  end

  test "a held lock writes tracks_realtime_retrigger and returns :ok" do
    user = user!()
    rows("UPDATE users SET status = 1 WHERE id = $1", [user.id])

    Redix.command!(rails_redis!(), ["SET", PerUserLock.key(user.id), "rails-token", "PX", "60000"])

    assert ExUnit.CaptureLog.capture_log(fn ->
             assert run(user.id, lock: [timeout_ms: 200]) == :ok
           end) =~ "lock_busy user_id=#{user.id}"

    assert commands() == [["tracks_realtime_retrigger", %{"user_id" => user.id}]]
  end

  test "success writes geocode_recent_points with since = start − 300" do
    %{call: [%{"now" => now}], expected: expected} = TracksFixtures.load!(ScratchRepo, "realtime")
    rows("UPDATE users SET status = 2 WHERE id = 1")

    assert run(1, now: now) == :ok

    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert actual_segments() == expected_segments(expected)
    assert commands() == [["geocode_recent_points", %{"user_id" => 1, "since" => now - 300}]]

    actions =
      for payload <- tracks_changed(),
          action <- ~w(created updated destroyed),
          _ <- payload[action],
          do: action

    assert Enum.sort(actions) == Enum.sort(for event <- expected["events"], do: event["action"])
  end

  test "a lost race stops the run and propagates" do
    user = user!()
    rows("UPDATE users SET status = 1 WHERE id = $1", [user.id])
    now = 1_790_000_000
    first = point!(user.id, now - 600, 12.3731, 51.3397)
    second = point!(user.id, now - 540, 12.3741, 51.3407)

    rows(
      "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, created_at, updated_at) " <>
        "VALUES ($1, '', to_timestamp($2::bigint) AT TIME ZONE 'UTC', to_timestamp($3::bigint) AT TIME ZONE 'UTC', " <>
        "ST_GeomFromText('LINESTRING(12.3731 51.3397,12.3741 51.3407)', 4326), now(), now())",
      [user.id, now - 600, now - 540]
    )

    assert ExUnit.CaptureLog.capture_log(fn ->
             assert run(user.id, now: now) == {:error, :race_lost}
           end) =~ "race_winner_not_visible"

    assert point_track_ids() == %{first => nil, second => nil}
    assert commands() == []
  end

  test "inactive and missing users are skipped" do
    user = user!()
    point!(user.id, 1_790_000_000, 12.3731, 51.3397)
    point!(user.id, 1_790_000_060, 12.3741, 51.3407)

    assert run(user.id, now: 1_790_000_100) == :ok
    assert run(424_242, now: 1_790_000_100) == :ok
    assert rows("SELECT count(*) FROM tracks") == [[0]]
    assert commands() == []
  end

  test "decodes version 1 payloads exactly" do
    assert RealtimeWorker.args_from_command(1, %{"user_id" => 7}) == {:ok, %{"user_id" => 7}}

    for bad <- [%{"user_id" => "7"}, %{"user_id" => 7, "extra" => 1}, %{}],
        do: assert(RealtimeWorker.args_from_command(1, bad) == {:error, "invalid_payload"})

    assert RealtimeWorker.args_from_command(2, %{"user_id" => 7}) ==
             {:error, "unsupported_version"}
  end
end
