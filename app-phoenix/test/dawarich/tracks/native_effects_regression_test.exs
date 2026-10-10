defmodule Dawarich.Tracks.NativeEffectsRegressionTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Tracks.{Builder, NativeChangesWorker}
  alias Dawarich.AfterCommit.Worker
  alias Dawarich.Transportation.{RecalculationStatus, ReclassifyTrackWorker}

  @t 1_790_000_000

  setup do
    start_oban(__MODULE__)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    old = System.get_env("DAWARICH_RAILS")
    cable = Application.get_env(:dawarich, :cable)
    System.put_env("DAWARICH_RAILS", "off")
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)

    rows(
      "INSERT INTO users(id,email,status,settings,created_at,updated_at) VALUES(1,'posthoc@example.test',1,'{}',now(),now())"
    )

    RecalculationStatus.clear(1)
    Dawarich.Redis.cache_command(["DEL", "transportation_mode_recalculation:user:1"])

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
      Application.put_env(:dawarich, :cable, cable)
      config = Application.fetch_env!(:dawarich, :redis)
      {:ok, conn} = Redix.start_link(config[:url], database: config[:cache_database])

      {:ok, _} =
        Redix.command(conn, [
          "DEL",
          RecalculationStatus.key(1),
          RecalculationStatus.key(1) <> ":events",
          "transportation_mode_recalculation:user:1"
        ])

      GenServer.stop(conn)
    end)

    :ok
  end

  defp points do
    for {stamp, lon} <- [{@t, 13.0}, {@t + 60, 13.001}] do
      [[id]] =
        rows(
          "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES(1,$1,ST_SetSRID(ST_MakePoint($2,52.0),4326)::geography,now(),now()) RETURNING id",
          [stamp, lon]
        )

      %{id: id, timestamp: stamp, lon: lon, lat: 52.0, tracker_id: nil, altitude: nil}
    end
  end

  test "track epoch invalidates a tile cached between effect and commit" do
    points = points()
    range = {@t - 60, @t + 120}
    before_epoch = Dawarich.Tiles.Http.epoch("tracks", 1, range, ScratchRepo)

    {:ok, observed} =
      ScratchRepo.transaction(fn ->
        assert {:ok, _} =
                 Builder.create_track!(ScratchRepo, %{id: 1, settings: %{}}, points, 70,
                   skip_segment_detection: true
                 )

        Task.async(fn ->
          {Dawarich.Tiles.Http.epoch("tracks", 1, range, ScratchRepo),
           rows("SELECT count(*) FROM tracks WHERE user_id=1")}
        end)
        |> Task.await()
      end)

    {mid_epoch, mid_rows} = observed
    after_epoch = Dawarich.Tiles.Http.epoch("tracks", 1, range, ScratchRepo)
    assert before_epoch == mid_epoch
    assert mid_rows == [[0]]
    refute mid_epoch == after_epoch

    assert {:error, :rollback} =
             ScratchRepo.transaction(fn ->
               Dawarich.Tracks.Effects.write!(ScratchRepo, 1, %{stamps: [@t], updated: []})
               ScratchRepo.rollback(:rollback)
             end)

    assert Dawarich.Tiles.Http.epoch("tracks", 1, range, ScratchRepo) == after_epoch
    assert length(effects()) == 1

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [
             inspect(NativeChangesWorker)
           ]) == [[0]]
  end

  test "native execution preserves Rails run ownership status total and progress receipt" do
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:transportation.reclassify_track", :oban)

    {:ok, "OK"} =
      Dawarich.Redis.cache_command([
        "SET",
        "transportation_mode_recalculation:user:1",
        <<0,
          Base.decode64!(
            "BAhbBnsJSSILc3RhdHVzBjoGRVRJIg9wcm9jZXNzaW5nBjsAVEkiD3N0YXJ0ZWRfYXQGOwBUSSIZMjAyNi0xMC0wN1QwMDowMDowMFoGOwBUSSIRdG90YWxfdHJhY2tzBjsAVGkGSSIVcHJvY2Vzc2VkX3RyYWNrcwY7AFRpAA=="
          )::binary>>
      ])

    before = RecalculationStatus.data(1)
    assert before["status"] == "processing"
    assert before["total_tracks"] == 1

    args = %{
      "track_id" => -1,
      "user_id" => 1,
      "report_progress" => true,
      "event_id" => Ecto.UUID.generate()
    }

    assert ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, args) == :ok
    after_state = RecalculationStatus.data(1)
    assert after_state == before
    refute RecalculationStatus.native?(1)

    assert rows("SELECT payload FROM phoenix.rails_commands WHERE kind='transport_progress'") == [
             [%{"user_id" => 1, "event_id" => args["event_id"]}]
           ]

    assert :ok = ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, args)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]

    stale =
      Jason.encode!(%{"status" => "completed", "processed_tracks" => 9, "total_tracks" => 9})

    assert {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", RecalculationStatus.key(1), stale])
    assert RecalculationStatus.data(1) == before

    assert :ok =
             ReclassifyTrackWorker.run(
               ScratchRepo,
               __MODULE__,
               Map.put(args, "event_id", Ecto.UUID.generate())
             )

    assert Dawarich.Redis.cache_command(["GET", RecalculationStatus.key(1)]) == {:ok, stale}
    assert RecalculationStatus.data(1) == before
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[2]]
  end

  test "track creation survives Cable stream lock timeout" do
    points = points()
    namespace = Dawarich.Cable.Bus.prefix() || ""
    {:ok, _} = Dawarich.Cable.PgStore.append(ScratchRepo, namespace, "probe", "probe")
    parent = self()

    task =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT namespace FROM phoenix.cable_streams WHERE namespace=$1 FOR UPDATE", [
            namespace
          ])

          send(parent, :stream_locked)
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive :stream_locked, 5_000

    result =
      try do
        ScratchRepo.transaction(fn ->
          rows("SET LOCAL lock_timeout = '100ms'")

          Builder.create_track!(ScratchRepo, %{id: 1, settings: %{}}, points, 70,
            skip_segment_detection: true
          )
        end)
      rescue
        e in Postgrex.Error -> {:publish_error, e.postgres[:code]}
      after
        send(task.pid, :release)
        Task.await(task)
      end

    assert match?({:ok, {:ok, _}}, result)
    assert rows("SELECT count(*) FROM tracks") == [[1]]
    assert rows("SELECT count(*) FROM points WHERE track_id IS NULL") == [[0]]
    assert [[payload]] = effects()
    assert_publish_replay(payload)
  end

  test "generation does not complete with missing tracks after Cable failure" do
    points()
    event = Ecto.UUID.generate()
    iso = fn t -> DateTime.from_unix!(t) |> DateTime.to_iso8601() end

    args = %{
      "event_id" => event,
      "user_id" => 1,
      "start_at" => iso.(@t - 60),
      "end_at" => iso.(@t + 120),
      "time_zone" => "UTC",
      "mode" => "bulk",
      "untracked_only" => true,
      "import_id" => nil,
      "low_priority" => false
    }

    assert :ok = Dawarich.Tracks.RangeWorker.run(ScratchRepo, __MODULE__, args)

    [[chunk]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
        inspect(Dawarich.Tracks.ChunkWorker)
      ])

    namespace = Dawarich.Cable.Bus.prefix() || ""
    {:ok, _} = Dawarich.Cable.PgStore.append(ScratchRepo, namespace, "probe", "probe")
    parent = self()

    task =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT namespace FROM phoenix.cable_streams WHERE namespace=$1 FOR UPDATE", [
            namespace
          ])

          send(parent, :stream_locked)
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive :stream_locked, 5_000

    try do
      ScratchRepo.checkout(fn ->
        rows("SET lock_timeout = '100ms'")

        try do
          assert :ok = Dawarich.Tracks.ChunkWorker.run(ScratchRepo, __MODULE__, chunk)
        after
          rows("SET lock_timeout = '0'")
        end
      end)
    after
      send(task.pid, :release)
      Task.await(task)
    end

    assert :ok =
             Dawarich.Tracks.BoundaryWorker.run(ScratchRepo, __MODULE__, %{
               "generation_id" => event,
               "poll_count" => 0
             })

    assert :ok = Dawarich.Tracks.RangeWorker.run(ScratchRepo, __MODULE__, args)
    assert :ok = Dawarich.Tracks.ChunkWorker.run(ScratchRepo, __MODULE__, chunk)
    state = rows("SELECT status,completed_chunks,tracks_created FROM phoenix.track_generations")
    assert state == [["completed", 1, 1]]
    assert rows("SELECT count(*) FROM tracks") == [[1]]
    assert [[payload]] = effects()
    rows("UPDATE tracks SET distance=123 WHERE id=$1", [hd(payload["payload"]["created"])])
    assert_publish_replay(payload)
    assert [%{"track" => %{"distance" => 123}}] = messages()
    rows("DELETE FROM phoenix.cable_events")
    assert :ok = Worker.run(ScratchRepo, payload)
    assert messages() == []
  end

  defp effects,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker=$1 AND args->>'operation'='tracks' ORDER BY id",
        [
          inspect(Worker)
        ]
      )

  defp messages,
    do:
      rows(
        "SELECT payload FROM phoenix.cable_events WHERE channel=$1 ORDER BY seq",
        [Dawarich.RailsMessages.broadcasting(["tracks", {:user, 1}])]
      )
      |> List.flatten()
      |> Enum.map(&Jason.decode!/1)

  defp assert_publish_replay(payload) do
    namespace = Dawarich.Cable.Bus.prefix() || ""
    parent = self()

    task =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT namespace FROM phoenix.cable_streams WHERE namespace=$1 FOR UPDATE", [
            namespace
          ])

          send(parent, :locked)
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive :locked, 5_000

    try do
      ScratchRepo.checkout(fn ->
        rows("SET lock_timeout = '100ms'")

        try do
          assert {:error, %Postgrex.Error{}} = Worker.run(ScratchRepo, payload)
        after
          rows("SET lock_timeout = '0'")
        end
      end)

      assert effects() == [[payload]]
      assert rows("SELECT count(*) FROM tracks") == [[1]]
    after
      send(task.pid, :release)
      Task.await(task)
    end

    assert :ok = Worker.run(ScratchRepo, payload)
    assert [%{"action" => "created"}] = messages()
  end

  test "review: failed epoch invalidation retains durable retry debt" do
    points = points()
    range = {@t - 60, @t + 120}
    before_epoch = Dawarich.Tiles.Http.epoch("tracks", 1, range, ScratchRepo)

    {:ok, "OK"} =
      Dawarich.Redis.command([
        "ACL",
        "SETUSER",
        "rxtracks_epochs",
        "on",
        "nopass",
        "~*",
        "+@all",
        "-set"
      ])

    {:ok, "OK"} = Dawarich.Redis.cache_command(["AUTH", "rxtracks_epochs", ""])

    try do
      assert {:ok, _} =
               Builder.create_track!(ScratchRepo, %{id: 1, settings: %{}}, points, 70,
                 skip_segment_detection: true
               )

      assert rows("SELECT count(*) FROM tracks") == [[1]]

      results =
        for queue <- [:tracks, :projections], do: Oban.drain_queue(__MODULE__, queue: queue)

      assert Enum.sum(Enum.map(results, & &1.failure)) == 1
      assert rows("SELECT state FROM oban.oban_jobs") == [["retryable"]]
      assert messages() == []
      {:ok, "OK"} = Dawarich.Redis.cache_command(["AUTH", "default", ""])
      after_epoch = Dawarich.Tiles.Http.epoch("tracks", 1, range, ScratchRepo)
      refute before_epoch == after_epoch

      results =
        for queue <- [:tracks, :projections],
            do: Oban.drain_queue(__MODULE__, queue: queue, with_scheduled: true)

      assert Enum.sum(Enum.map(results, & &1.success)) == 1
      assert rows("SELECT state FROM oban.oban_jobs") == [["completed"]]
      assert [%{"action" => "created"}] = messages()
      assert {:ok, token} = Dawarich.Redis.cache_command(["GET", "tracks:tile_epoch:1:2026"])
      assert is_binary(token)
    after
      Dawarich.Redis.cache_command(["AUTH", "default", ""])
      Dawarich.Redis.command(["ACL", "DELUSER", "rxtracks_epochs"])
    end
  end

  test "review: legacy notification jobs retain retry debt and a stable receipt" do
    assert {:ok, track} =
             Builder.create_track!(ScratchRepo, %{id: 1, settings: %{}}, points(), 70,
               skip_segment_detection: true
             )

    payload = %{
      "user_id" => 1,
      "created" => [track.id],
      "updated" => [],
      "destroyed" => [],
      "min_ts" => @t,
      "max_ts" => @t + 60
    }

    rows("DELETE FROM oban.oban_jobs")
    job = ScratchRepo.insert!(NativeChangesWorker.new(payload), prefix: "oban")

    {:ok, "OK"} =
      Dawarich.Redis.command([
        "ACL",
        "SETUSER",
        "rxtracks_legacy",
        "on",
        "nopass",
        "~*",
        "+@all",
        "-set"
      ])

    {:ok, "OK"} = Dawarich.Redis.cache_command(["AUTH", "rxtracks_legacy", ""])

    try do
      assert %{failure: 1, success: 0} = Oban.drain_queue(__MODULE__, queue: :tracks)
      assert rows("SELECT state FROM oban.oban_jobs") == [["retryable"]]
      assert messages() == []
      {:ok, "OK"} = Dawarich.Redis.cache_command(["AUTH", "default", ""])

      assert %{failure: 0, success: 1} =
               Oban.drain_queue(__MODULE__, queue: :tracks, with_scheduled: true)

      assert [%{"action" => "created", "track" => %{"id" => id}}] = messages()
      assert id == track.id
      assert :ok = NativeChangesWorker.perform(job)
      assert length(messages()) == 1

      assert rows("SELECT count(*) FROM phoenix.processed_commands WHERE handler='after_commit'") ==
               [[1]]
    after
      Dawarich.Redis.cache_command(["AUTH", "default", ""])
      Dawarich.Redis.command(["ACL", "DELUSER", "rxtracks_legacy"])
    end
  end

  test "review: Rails terminal status remains authoritative over stale native completion" do
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:transportation.reclassify_track", :oban)

    raw =
      Base.decode64!(
        "BAhbBnsJSSILc3RhdHVzBjoGRVRJIg9wcm9jZXNzaW5nBjsAVEkiD3N0YXJ0ZWRfYXQGOwBUSSIZMjAyNi0xMC0wN1QwMDowMDowMFoGOwBUSSIRdG90YWxfdHJhY2tzBjsAVGkGSSIVcHJvY2Vzc2VkX3RyYWNrcwY7AFRpAA=="
      )

    legacy_key = "transportation_mode_recalculation:user:1"
    {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", legacy_key, <<0, raw::binary>>])

    stale =
      Jason.encode!(%{"status" => "completed", "total_tracks" => 9, "processed_tracks" => 9})

    {:ok, "OK"} =
      Dawarich.Redis.cache_command(["SET", RecalculationStatus.key(1), stale, "EX", "300"])

    assert RecalculationStatus.data(1)["total_tracks"] == 1

    args = %{
      "track_id" => -1,
      "user_id" => 1,
      "report_progress" => true,
      "event_id" => Ecto.UUID.generate()
    }

    assert :ok = ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, args)

    assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='transport_progress'") ==
             [[1]]

    completed =
      raw
      |> :binary.replace(<<15, "processing">>, <<14, "completed">>)
      |> :binary.replace(<<105, 0>>, <<105, 6>>)

    {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", legacy_key, <<0, completed::binary>>])
    {:ok, expected} = Dawarich.RailsCache.get(legacy_key)
    assert expected["status"] == "completed"
    assert expected["processed_tracks"] == 1
    actual = RecalculationStatus.data(1)
    assert actual == expected

    older =
      Jason.encode!(%{
        "status" => "completed",
        "total_tracks" => 9,
        "processed_tracks" => 9,
        "started_at" => "2026-10-06T23:00:00Z"
      })

    assert {:ok, "OK"} =
             Dawarich.Redis.cache_command(["SET", RecalculationStatus.key(1), older, "EX", "300"])

    assert RecalculationStatus.data(1) == expected
    RecalculationStatus.start(1, 2, ~U[2026-10-07 01:00:00Z])
    assert RecalculationStatus.data(1)["total_tracks"] == 2
    assert RecalculationStatus.data(1)["started_at"] == "2026-10-07T01:00:00Z"
  end

  test "review: Rails failed status remains authoritative over stale native completion" do
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:transportation.reclassify_track", :oban)

    raw =
      Base.decode64!(
        "BAhbBnsJSSILc3RhdHVzBjoGRVRJIg9wcm9jZXNzaW5nBjsAVEkiD3N0YXJ0ZWRfYXQGOwBUSSIZMjAyNi0xMC0wN1QwMDowMDowMFoGOwBUSSIRdG90YWxfdHJhY2tzBjsAVGkGSSIVcHJvY2Vzc2VkX3RyYWNrcwY7AFRpAA=="
      )

    legacy_key = "transportation_mode_recalculation:user:1"
    {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", legacy_key, <<0, raw::binary>>])

    stale =
      Jason.encode!(%{"status" => "completed", "total_tracks" => 9, "processed_tracks" => 9})

    {:ok, "OK"} =
      Dawarich.Redis.cache_command(["SET", RecalculationStatus.key(1), stale, "EX", "300"])

    assert RecalculationStatus.data(1)["total_tracks"] == 1

    args = %{
      "track_id" => -1,
      "user_id" => 1,
      "report_progress" => true,
      "event_id" => Ecto.UUID.generate()
    }

    assert :ok = ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, args)

    assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='transport_progress'") ==
             [[1]]

    completed =
      raw
      |> :binary.replace(<<15, "processing">>, <<11, "failed">>)
      |> :binary.replace(<<105, 0>>, <<105, 6>>)

    {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", legacy_key, <<0, completed::binary>>])
    {:ok, expected} = Dawarich.RailsCache.get(legacy_key)
    assert expected["status"] == "failed"
    assert expected["processed_tracks"] == 1
    actual = RecalculationStatus.data(1)
    assert actual == expected

    older =
      Jason.encode!(%{
        "status" => "completed",
        "total_tracks" => 9,
        "processed_tracks" => 9,
        "started_at" => "2026-10-06T23:00:00Z"
      })

    assert {:ok, "OK"} =
             Dawarich.Redis.cache_command(["SET", RecalculationStatus.key(1), older, "EX", "300"])

    assert RecalculationStatus.data(1) == expected
    RecalculationStatus.start(1, 2, ~U[2026-10-07 01:00:00Z])
    assert RecalculationStatus.data(1)["total_tracks"] == 2
    assert RecalculationStatus.data(1)["started_at"] == "2026-10-07T01:00:00Z"
  end
end
