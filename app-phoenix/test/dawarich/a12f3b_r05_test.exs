defmodule Dawarich.A12f3bR05Test do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.RealtimeWorker
  alias Dawarich.Transportation.{RecalculationStatus, ReclassifyTrackWorker}

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)

  setup do
    start_oban(__MODULE__)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    old = System.get_env("DAWARICH_RAILS")
    cable = Application.get_env(:dawarich, :cable)
    System.put_env("DAWARICH_RAILS", "off")

    for key <-
          ~w(command:tracks.generate_range command:geocoding.reverse_point command:transportation.reclassify_track command:trips.calculate),
        do: Ownership.put!(ScratchRepo, key, :sidekiq, pinned: true)

    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)

    rows(
      "INSERT INTO users(id,email,status,settings,created_at,updated_at) VALUES(1,'rxtracks@example.test',1,$1,now(),now()),(2,'other@example.test',1,'{}',now(),now())",
      [%{"timezone" => "UTC"}]
    )

    RecalculationStatus.clear(1)

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
      Application.put_env(:dawarich, :cable, cable)
    end)

    :ok
  end

  @tag a12f3b_case: "R05k01"
  test "tracks_changed native producer reaches its source terminal effect" do
    from = ~U[2024-12-31 12:00:00Z]
    to = ~U[2026-01-01 12:00:00Z]

    tokens =
      for year <- [2024, 2025, 2026] do
        key = "tracks:tile_epoch:1:#{year}"
        Dawarich.Redis.cache_command(["SET", key, "before"])
        key
      end

    [[id]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES(1,$1,$2,ST_GeomFromText('LINESTRING(1 1,2 2)',4326),now(),now()) RETURNING id",
        [DateTime.to_naive(from), DateTime.to_naive(to)]
      )

    for _ <- 1..2, do: assert(Dawarich.ReleaseOperations.OrphanedTracks.run(ScratchRepo) == :ok)
    assert rows("SELECT id FROM tracks") == []
    Dawarich.Test.AfterCommit.drain(ScratchRepo)

    for key <- tokens do
      assert {:ok, token} = Dawarich.Redis.cache_command(["GET", key])
      assert is_binary(token) and token != "before"
    end

    assert [[channel, payload]] = rows("SELECT channel,payload FROM phoenix.cable_events")
    assert channel == Dawarich.RailsMessages.broadcasting(["tracks", {:user, 1}])
    assert Jason.decode!(payload) == %{"action" => "destroyed", "track_id" => id}
    assert reverse("tracks_changed") == []

    [[created]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,distance,avg_speed,duration,original_path,created_at,updated_at) VALUES(1,$1,$2,35,2.0,10,ST_GeomFromText('LINESTRING(1 1,2 2)',4326),now(),now()) RETURNING id",
        [DateTime.to_naive(from), DateTime.to_naive(to)]
      )

    Dawarich.Tracks.Effects.write!(ScratchRepo, 1, %{stamps: [from, to], created: [created]})
    Dawarich.Test.AfterCommit.drain(ScratchRepo)
    [[message]] = rows("SELECT payload FROM phoenix.cable_events ORDER BY seq DESC LIMIT 1")
    message = Jason.decode!(message)
    assert message["action"] == "created"
    assert message["track"]["id"] == created
    assert message["track"]["original_path"] == "LINESTRING (1 1, 2 2)"
    assert message["track"]["distance"] == 35
    assert message["track"]["start_at"] == "2024-12-31T12:00:00Z"
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Tracks.Effects.write!(ScratchRepo, 1, %{stamps: [from, to], destroyed: [id]})
    assert [[%{"destroyed" => [^id]}]] = reverse("tracks_changed")
  end

  @tag a12f3b_case: "R05k02"
  test "geocode_recent_points native producer reaches its source terminal effect" do
    rows(
      "INSERT INTO instance_settings(key,value,created_at,updated_at) VALUES('photon_api_host',$1,now(),now())",
      ["fake.example.test"]
    )

    [[eligible]] = point(1, DateTime.add(@now, -299), nil)
    point(1, DateTime.add(@now, -300), nil)
    point(1, DateTime.add(@now, -10), DateTime.to_naive(@now))
    point(2, DateTime.add(@now, -10), nil)

    for _ <- 1..2,
        do:
          assert(
            RealtimeWorker.run(ScratchRepo, __MODULE__, %{"user_id" => 1}, now: @epoch) == :ok
          )

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               inspect(Dawarich.Geocoding.ReversePointWorker)
             ])

    assert args["point_ids"] == [eligible]
    assert args["force"] == false
    assert args["cursor"] == 0
    assert reverse("geocode_recent_points") == []
    System.delete_env("DAWARICH_RAILS")
    assert RealtimeWorker.run(ScratchRepo, __MODULE__, %{"user_id" => 1}, now: @epoch) == :ok
    assert [[reverse]] = reverse("geocode_recent_points")
    assert reverse["since"] == @epoch - 300
  end

  @tag a12f3b_case: "R05k03"
  test "transport_progress native producer reaches its source terminal effect" do
    RecalculationStatus.start(1, 1, @now)
    event = Ecto.UUID.generate()
    args = %{"track_id" => -1, "report_progress" => true, "user_id" => 1, "event_id" => event}
    for _ <- 1..2, do: assert(ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, args) == :ok)
    Dawarich.Test.AfterCommit.drain(ScratchRepo)
    assert RecalculationStatus.data(1)["processed_tracks"] == 1
    assert RecalculationStatus.data(1)["status"] == "completed"
    assert [[channel, payload]] = rows("SELECT channel,payload FROM phoenix.cable_events")
    assert channel == Dawarich.RailsMessages.broadcasting(["tracks", {:user, 1}])
    assert Jason.decode!(payload)["action"] == "transport_progress"
    assert reverse("transport_progress") == []
    RecalculationStatus.clear(1)
    orphan = Map.put(args, "event_id", Ecto.UUID.generate())
    for _ <- 1..2, do: assert(ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, orphan) == :ok)
    Dawarich.Test.AfterCommit.drain(ScratchRepo)
    assert RecalculationStatus.data(1)["processed_tracks"] == 1
    System.delete_env("DAWARICH_RAILS")
    RecalculationStatus.clear(1)

    assert ReclassifyTrackWorker.run(
             ScratchRepo,
             __MODULE__,
             Map.put(args, "event_id", Ecto.UUID.generate())
           ) == :ok

    assert [[%{"user_id" => 1}]] = reverse("transport_progress")
  end

  @tag a12f3b_case: "R05k04"
  test "trips.calculate native producer reaches its source terminal effect" do
    [[trip]] =
      rows(
        "INSERT INTO trips(user_id,name,started_at,ended_at,created_at,updated_at) VALUES(1,'Synthetic',$1,$2,now(),now()) RETURNING id",
        [DateTime.to_naive(DateTime.add(@now, -86400)), DateTime.to_naive(@now)]
      )

    ctx = %{repo: ScratchRepo, user_id: 1, settings: %{}, now: @now}
    for _ <- 1..2, do: Dawarich.Imports.Trek.Records.calculate!(ctx, trip, true)

    assert [[event, payload]] =
             rows(
               "SELECT event_id::text,payload FROM job_outbox WHERE command_type='trips.calculate'"
             )

    assert payload == %{"trip_id" => trip, "distance_unit" => "km"}
    assert Ecto.UUID.cast(event) == {:ok, event}
    assert reverse("trips.calculate") == []

    assert Dawarich.Jobs.Dispatch.run(
             repo: ScratchRepo,
             oban: __MODULE__,
             now: DateTime.utc_now()
           ) == %{dispatched: 1}

    assert [[job_args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               inspect(Dawarich.Trips.CalculateWorker)
             ])

    assert job_args == Map.put(payload, "event_id", event)
    old_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, old_repo) end)
    job = %Oban.Job{args: Map.put(payload, "event_id", event), attempt: 1, max_attempts: 3}
    for _ <- 1..2, do: assert(Dawarich.Trips.CalculateWorker.perform(job) == :ok)

    assert rows("SELECT kind FROM phoenix.trip_events ORDER BY id") == [
             ["distance"],
             ["countries"],
             ["finished"]
           ]

    System.delete_env("DAWARICH_RAILS")
    Dawarich.Imports.Trek.Records.calculate!(ctx, trip, true)
    assert [[%{"trip_id" => ^trip}]] = reverse("trips.calculate")
    Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    rows("DELETE FROM phoenix.rails_commands")
    Dawarich.Imports.Trek.Records.calculate!(ctx, trip, true)
    assert reverse("trips.calculate") == []
  end

  defp point(user, at, geocoded),
    do:
      rows(
        "INSERT INTO points(user_id,timestamp,created_at,updated_at,reverse_geocoded_at) VALUES($1,$2,$3,$3,$4) RETURNING id",
        [user, @epoch - 600, DateTime.to_naive(at), geocoded]
      )

  defp reverse(kind), do: rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1", [kind])
end
