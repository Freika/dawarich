defmodule Dawarich.ReleaseOperations.TransportationTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperations.Transportation

  @oban Dawarich.ReleaseOperations.TransportationTest.Oban

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{user: Wave6Fixtures.user!()}
  end

  test "missing scope sends tracks without segments or with unknown mode", %{user: user} do
    bare = Wave6Fixtures.track!(user, %{"dominant_mode" => 2})
    unknown = Wave6Fixtures.track!(user, %{"dominant_mode" => 0})
    Wave6Fixtures.segment!(unknown)
    walked = Wave6Fixtures.track!(user, %{"dominant_mode" => 2})
    Wave6Fixtures.segment!(walked, %{"transportation_mode" => 2})
    deleted = Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})
    Wave6Fixtures.track!(deleted)

    {_id, :ok} = run(%{"scope" => "missing", "from_track_id" => 0})

    assert [[%{"user_id" => ^user, "track_ids" => [^bare, ^unknown], "run_at" => _}]] = commands()
  end

  test "slices of 100 are one row per user, 30 s apart", %{user: user} do
    rows(
      """
      INSERT INTO tracks (user_id, start_at, end_at, original_path, created_at, updated_at)
      SELECT $1, timestamp '2020-01-01' + g * interval '1 hour',
        timestamp '2020-01-01' + g * interval '1 hour' + interval '30 minutes',
        ST_GeomFromText('LINESTRING(12.3731 51.3397, 12.3831 51.3497)', 4326), now(), now()
      FROM generate_series(1, 101) g
      """,
      [user]
    )

    before = System.os_time(:second)
    {_id, :ok} = run(%{"scope" => "missing", "from_track_id" => 0})

    assert [[first], [second]] = commands()
    assert length(first["track_ids"]) == 100
    assert length(second["track_ids"]) == 1
    assert first["run_at"] >= before and first["run_at"] <= System.os_time(:second)
    assert second["run_at"] - first["run_at"] == 30
  end

  test "all scope includes tracks of deleted users, as Rails does", %{user: user} do
    live = Wave6Fixtures.track!(user)
    deleted = Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})
    gone = Wave6Fixtures.track!(deleted)

    {_id, :ok} = run(%{"scope" => "all", "from_track_id" => 0})

    assert commands() |> Enum.flat_map(fn [payload] -> payload["track_ids"] end) |> Enum.sort() ==
             [live, gone]
  end

  test "missing stops on a short page; all continues every 600 s until empty", %{user: user} do
    tracks = for _ <- 1..3, do: Wave6Fixtures.track!(user)

    {missing, :ok} = run(%{"scope" => "missing", "from_track_id" => 0})
    assert status(missing) == "completed"
    assert jobs() == []

    {all, :ok} = run(%{"scope" => "all", "from_track_id" => 0})
    assert status(all) == "running"
    assert [[successor, delay]] = jobs()

    assert successor == %{
             "version" => 1,
             "operation_id" => all,
             "cursor" => %{"scope" => "all", "from_track_id" => List.last(tracks)}
           }

    assert delay >= 599 and delay <= 601

    assert ReleaseOperations.run(ScratchRepo, @oban, Transportation, job(successor)) == :ok
    assert status(all) == "completed"
    assert length(jobs()) == 1
  end

  test "decodes version 1 payloads exactly" do
    payload = %{"scope" => "missing", "from_track_id" => 0}

    assert Transportation.args_from_command(1, payload) ==
             {:ok, %{"version" => 1, "cursor" => payload}}

    for invalid <- [
          Map.put(payload, "extra", 1),
          %{payload | "scope" => "some"},
          %{payload | "from_track_id" => "0"},
          Map.delete(payload, "scope")
        ] do
      assert Transportation.args_from_command(1, invalid) == {:error, "invalid_payload"}
    end

    assert Transportation.args_from_command(2, payload) == {:error, "unsupported_version"}
  end

  defp run(cursor) do
    id = Ecto.UUID.generate()
    args = %{"version" => 1, "event_id" => id, "cursor" => cursor}
    {id, ReleaseOperations.run(ScratchRepo, @oban, Transportation, job(args))}
  end

  defp job(args), do: %Oban.Job{args: args, attempt: 1, max_attempts: 10}

  defp commands,
    do:
      rows(
        "SELECT payload FROM phoenix.rails_commands WHERE kind = 'release_reclassify_tracks' ORDER BY id"
      )

  defp jobs,
    do:
      rows(
        "SELECT args, extract(epoch FROM scheduled_at - inserted_at)::float FROM oban.oban_jobs ORDER BY id"
      )

  defp status(id) do
    [[status]] =
      rows("SELECT status FROM phoenix.release_operations WHERE id = $1", [Ecto.UUID.dump!(id)])

    status
  end
end
