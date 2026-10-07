defmodule Dawarich.Tracks.NativeEffectsRegressionTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Tracks.{Builder, NativeChangesWorker}
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
    before_epoch = Dawarich.Tiles.Http.epoch("tracks", 1, range)

    {:ok, observed} =
      ScratchRepo.transaction(fn ->
        assert {:ok, _} =
                 Builder.create_track!(ScratchRepo, %{id: 1, settings: %{}}, points, 70,
                   skip_segment_detection: true
                 )

        Task.async(fn ->
          {Dawarich.Tiles.Http.epoch("tracks", 1, range),
           rows("SELECT count(*) FROM tracks WHERE user_id=1")}
        end)
        |> Task.await()
      end)

    {mid_epoch, mid_rows} = observed
    after_epoch = Dawarich.Tiles.Http.epoch("tracks", 1, range)
    assert before_epoch == mid_epoch
    assert mid_rows == [[0]]
    refute mid_epoch == after_epoch

    assert {:error, :rollback} =
             ScratchRepo.transaction(fn ->
               Dawarich.Tracks.Effects.write!(ScratchRepo, 1, %{stamps: [@t], updated: []})
               ScratchRepo.rollback(:rollback)
             end)

    assert Dawarich.Tiles.Http.epoch("tracks", 1, range) == after_epoch
    assert length(effects()) == 1
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
    rows("UPDATE tracks SET distance=123 WHERE id=$1", [hd(payload["created"])])
    assert_publish_replay(payload)
    assert [%{"track" => %{"distance" => 123}}] = messages()
    rows("DELETE FROM phoenix.cable_events")
    assert :ok = NativeChangesWorker.run(ScratchRepo, payload)
    assert [%{"track" => %{"distance" => 123}}] = messages()
  end

  defp effects,
    do:
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [
        inspect(NativeChangesWorker)
      ])

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
      assert_raise Postgrex.Error, fn ->
        ScratchRepo.transaction(fn ->
          rows("SET LOCAL lock_timeout = '100ms'")
          NativeChangesWorker.run(ScratchRepo, payload)
        end)
      end

      assert effects() == [[payload]]
      assert rows("SELECT count(*) FROM tracks") == [[1]]
    after
      send(task.pid, :release)
      Task.await(task)
    end

    assert :ok = NativeChangesWorker.run(ScratchRepo, payload)
    assert [%{"action" => "created"}] = messages()
  end
end
