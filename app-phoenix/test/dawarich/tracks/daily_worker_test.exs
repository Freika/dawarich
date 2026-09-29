defmodule Dawarich.Tracks.DailyWorkerTest do
  use Dawarich.TracksCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.{DailyWorker, RangeWorker}

  @slot 1_759_050_000
  @now ~U[2025-09-28 09:05:00.123456Z]
  @cron_key "cron:daily_track_generation_job"
  @range_key "command:tracks.generate_range"

  setup do
    for name <- ~w(SELF_HOSTED TIME_ZONE) do
      previous = System.get_env(name)

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    System.delete_env("TIME_ZONE")
    :ok
  end

  defp daily_user!(settings \\ %{"timezone" => "Europe/Berlin"}, status \\ 1) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, status, points_count, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, 2, now(), now()) RETURNING id",
        ["daily-#{System.unique_integer([:positive])}@example.test", settings, status]
      )

    id
  end

  defp with_points!(user_id, timestamps) do
    for ts <- timestamps, do: point!(user_id, ts, 12.3731, 51.3397 + (ts - @slot) / 1.0e7)
    user_id
  end

  defp payload(user_id, start_ts, zone \\ "Europe/Berlin") do
    %{
      "user_id" => user_id,
      "start_at" => iso(start_ts),
      "end_at" => "2025-09-28T09:05:00.123456Z",
      "time_zone" => zone,
      "mode" => "daily",
      "untracked_only" => false,
      "import_id" => nil,
      "low_priority" => false
    }
  end

  defp range_jobs,
    do:
      rows("SELECT args FROM oban.oban_jobs WHERE worker = $1 ORDER BY id", [inspect(RangeWorker)])
      |> List.flatten()

  defp commands,
    do: rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")

  defp run(opts \\ []), do: DailyWorker.run(ScratchRepo, oban(), @slot, [now: @now] ++ opts)

  defp owned! do
    :ok = Ownership.put!(ScratchRepo, @cron_key, :oban)
    :ok = Ownership.put!(ScratchRepo, @range_key, :oban)
  end

  test "event_id equals Rails' uuid_v5" do
    assert DailyWorker.event_id(1_759_050_000, 42) == "9aa38e8c-dd08-56d2-9de5-bc6a4e5dbab5"
  end

  test "the slot is the cron minute the job was inserted in" do
    assert DailyWorker.slot(%Oban.Job{inserted_at: ~U[2025-09-28 09:00:07.512345Z]}) == @slot
  end

  test "starts a generation per due user with a stable id" do
    :ok = Ownership.put!(ScratchRepo, @cron_key, :oban)
    :ok = Ownership.put!(ScratchRepo, @range_key, :oban)

    fresh = daily_user!() |> with_points!([@slot - 7_200, @slot - 7_140])
    caught_up = daily_user!(%{"timezone" => "Europe/Berlin"}, 2)
    track!(caught_up, "b", @slot - 90_000, @slot - 86_400)
    with_points!(caught_up, [@slot - 3_600, @slot - 3_540])
    idle = daily_user!() |> with_points!([@slot - 90_000])
    track!(idle, "c", @slot - 90_000, @slot - 80_000)

    expected = [
      Map.put(payload(fresh, @slot - 7_200), "event_id", DailyWorker.event_id(@slot, fresh)),
      Map.put(
        payload(caught_up, @slot - 86_399),
        "event_id",
        DailyWorker.event_id(@slot, caught_up)
      )
    ]

    assert run() == :ok
    assert range_jobs() == expected

    assert run() == :ok
    assert range_jobs() == expected ++ expected

    for args <- range_jobs(), do: assert(RangeWorker.run(ScratchRepo, oban(), args) == :ok)

    assert rows("SELECT id FROM phoenix.track_generations ORDER BY user_id") ==
             Enum.map(expected, &[Ecto.UUID.dump!(&1["event_id"])])

    assert rows("SELECT user_id, total_chunks FROM phoenix.track_generations ORDER BY user_id") ==
             [[fresh, 1], [caught_up, 2]]

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker = 'Dawarich.Tracks.ChunkWorker'"
           ) == [[3]]
  end

  test "a blocked history writes tracks_throttled_backfill" do
    System.put_env("SELF_HOSTED", "false")
    :ok = Ownership.put!(ScratchRepo, @cron_key, :oban)
    :ok = Ownership.put!(ScratchRepo, @range_key, :oban)
    user = daily_user!()

    rows(
      "INSERT INTO points (user_id, timestamp, created_at, updated_at) " <>
        "SELECT $1, $2 + g, now(), now() FROM generate_series(1, 100001) AS g",
      [user, @slot - 200_000]
    )

    assert run() == :ok
    assert commands() == [["tracks_throttled_backfill", %{"user_id" => user}]]
    assert range_jobs() == []
  end

  test "Sidekiq-owned range command routes through Rails" do
    :ok = Ownership.put!(ScratchRepo, @cron_key, :oban)
    user = daily_user!() |> with_points!([@slot - 7_200, @slot - 7_140])

    assert run() == :ok
    assert commands() == [["tracks_generate_range", payload(user, @slot - 7_200)]]
    assert range_jobs() == []
  end

  test "a released cron key cancels" do
    daily_user!() |> with_points!([@slot - 7_200, @slot - 7_140])

    assert run() == {:cancel, :not_owner}
    assert commands() == []
    assert range_jobs() == []
  end

  test "time zone falls back when Postgres does not know it" do
    :ok = Ownership.put!(ScratchRepo, @cron_key, :oban)
    :ok = Ownership.put!(ScratchRepo, @range_key, :oban)
    rails_name = daily_user!(%{"timezone" => "Berlin"}) |> with_points!([@slot - 7_200])
    iana = daily_user!(%{"timezone" => "Europe/Berlin"}) |> with_points!([@slot - 7_200])

    assert run() == :ok

    assert Enum.map(range_jobs(), &{&1["user_id"], &1["time_zone"]}) == [
             {rails_name, "UTC"},
             {iana, "Europe/Berlin"}
           ]
  end

  test "one user's SQL error rolls back only that user" do
    owned!()

    [first, failing, last] =
      for _ <- 1..3, do: daily_user!() |> with_points!([@slot - 7_200, @slot - 7_140])

    fail_one = fn
      ^failing -> ScratchRepo.query!("SELECT 1 / 0", [], log: false)
      _user_id -> :ok
    end

    log =
      ExUnit.CaptureLog.capture_log(fn -> assert run(hook: fail_one) == :ok end)

    assert log =~ "Failed to process daily tracks for user #{failing}"
    assert Enum.map(range_jobs(), & &1["user_id"]) == [first, last]
  end

  test "a user whose latest track ends after the slot keeps it" do
    owned!()
    user = daily_user!() |> with_points!([@slot + 200, @slot + 260])
    track = track!(user, "realtime", @slot - 600, @slot + 120)

    rows(
      "INSERT INTO shared_links (name, resource_type, resource_id, user_id, created_at, updated_at) " <>
        "VALUES ('trip', 1, $1, $2, now(), now())",
      [track, user]
    )

    assert run() == :ok
    assert [%{"start_at" => start_at, "end_at" => end_at} = args] = range_jobs()
    assert {start_at, end_at} == {iso(@slot + 121), "2025-09-28T09:05:00.123456Z"}

    assert RangeWorker.run(ScratchRepo, oban(), args) == :ok

    assert rows("SELECT id FROM tracks") == [[track]]
    assert rows("SELECT resource_id FROM shared_links") == [[track]]
    assert [["running", 1, 0, 0, 0, nil]] = generation(args["event_id"])
  end
end
