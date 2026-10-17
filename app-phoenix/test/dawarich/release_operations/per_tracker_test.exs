defmodule Dawarich.ReleaseOperations.PerTrackerTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.ReleaseOperations.PerTracker, as: Worker
  alias Dawarich.Wave6Fixtures

  @now ~U[2026-10-03 12:00:00Z]
  @source Path.expand("../../fixtures/a12d1b3/Records.json", __DIR__)

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_tracker
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    start_oban(:per_tracker)
    :ok
  end

  test "selects source pending users and records independent inclusive stagger delays" do
    source = Fixtures.case!("tracker_stagger")
    Fixtures.load!(ScratchRepo, source)

    extra =
      for id <- 170_102..170_105 do
        user =
          hd(source["input"]["users"])
          |> Map.merge(%{"id" => id, "email" => "tracker-#{id}@example.invalid"})

        Fixtures.row!(ScratchRepo, "users", user)
        id
      end

    [non_records, legacy, nil_track, nil_point] = extra

    import =
      hd(source["input"]["imports"])
      |> Map.merge(%{"id" => 170_802, "source" => 0, "user_id" => non_records})

    Fixtures.row!(ScratchRepo, "imports", import)
    point = hd(source["input"]["points"])

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{
        "id" => 190_001,
        "user_id" => non_records,
        "tracker_id" => "legacy-import-170802",
        "import_id" => 170_802
      })
    )

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{
        "id" => 190_002,
        "user_id" => legacy,
        "tracker_id" => "google-maps-timeline-export"
      })
    )

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{"id" => 190_003, "user_id" => nil_point})
    )

    Wave6Fixtures.track!(nil_track)
    args = args(nil)
    for draw <- [0, 3600, 7], do: send(self(), {:draw, draw})

    rand = fn 0..3600 ->
      receive do
        {:draw, draw} -> draw
      after
        0 -> 0
      end
    end

    assert run(args, rand: rand) == :ok
    assert run(args, rand: fn _ -> flunk("duplicate draw") end) == :ok
    children = rows("SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY id")

    assert Enum.map(children, fn [args, _] -> args["cursor"]["request"]["user_id"] end) == [
             170_101,
             legacy,
             nil_track
           ]

    assert Enum.map(children, fn [_, at] ->
             DateTime.from_naive!(at, "Etc/UTC") |> DateTime.to_unix(:microsecond)
           end) ==
             Enum.map([0, 3600, 7], &(DateTime.to_unix(@now, :microsecond) + &1 * 1_000_000))

    for [child, _] <- children do
      request = child["cursor"]["request"]
      assert request["ambient_zone"] == "Europe/Berlin"
      assert {:ok, _} = Ecto.UUID.cast(request["source_job_id"])
    end
  end

  test "repairs original files first and retries stale tracks after a zero-count rerun" do
    source = Fixtures.case!("tracker_records")
    Fixtures.load!(ScratchRepo, source)
    missing = hd(source["input"]["imports"]) |> Map.put("id", 170_800)
    Fixtures.row!(ScratchRepo, "imports", missing)
    dir = Path.join(System.tmp_dir!(), "per-tracker-#{Ecto.UUID.generate()}")
    File.mkdir_p!(Path.join([dir, "storage", "a1", "2d"]))
    File.mkdir_p!(Path.join(dir, "tmp"))
    File.cp!(@source, Path.join([dir, "storage", "a1", "2d", "a12d1b3-records-source"]))
    on_exit(fn -> File.rm_rf!(dir) end)

    opts = [
      services: %{
        "test" => %{service: "local", stored_service: "test", root: Path.join(dir, "storage")}
      },
      download_opts: [temp_dir: Path.join(dir, "tmp")]
    ]

    args = args(170_101)
    parent = self()

    opts =
      Keyword.put(opts, :after_repair, fn devices, raw ->
        send(parent, {:repairs, devices, raw})
      end)

    assert_raise RuntimeError, "after_repair", fn ->
      run(args, Keyword.put(opts, :phase, fn :tracks, _, _ -> raise "after_repair" end))
    end

    assert_receive {:repairs, 3, 3}

    assert rows("SELECT id,tracker_id FROM points ORDER BY id") ==
             Enum.map(source["expected"]["rows"]["points"], fn p -> [p["id"], p["tracker_id"]] end)

    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    assert run(args, opts) == :ok
    assert_receive {:repairs, 0, 0}
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert rows("SELECT count(*) FROM digests") == [[2]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert run(args, opts) == :ok
    refute_receive {:repairs, _, _}, 0
    assert File.ls!(Path.join(dir, "tmp")) == []

    assert Worker.needs_recalculation?(ScratchRepo, 170_101)
    track = Wave6Fixtures.track!(170_101, %{"tracker_id" => "real-device"})
    rows("UPDATE points SET track_id=$1,tracker_id='real-device'", [track])
    refute Worker.needs_recalculation?(ScratchRepo, 170_101)
    rows("UPDATE tracks SET tracker_id=NULL WHERE id=$1", [track])
    assert Worker.needs_recalculation?(ScratchRepo, 170_101)
    rows("UPDATE tracks SET tracker_id='real-device' WHERE id=$1", [track])
    rows("UPDATE points SET tracker_id='other' WHERE id=170201")
    assert Worker.needs_recalculation?(ScratchRepo, 170_101)
    hold_lease!(ScratchRepo, "tracks:per_user_lock:170101", "other")

    assert run(args(170_101), Keyword.put(opts, :range_opts, lock: [timeout_ms: 0])) ==
             {:error, :lock_busy}

    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert run(args(-1), opts) == :ok
  end

  defp args(user_id) do
    id = Ecto.UUID.generate()

    {:ok, decoded} =
      Worker.args_from_command(1, %{
        "user_id" => user_id,
        "source_job_id" => id,
        "ambient_zone" => "Europe/Berlin"
      })

    Map.put(decoded, "event_id", id)
  end

  defp run(args, opts),
    do:
      Ops.run(
        ScratchRepo,
        :per_tracker,
        Worker,
        %Oban.Job{args: args, attempt: 1, max_attempts: 26},
        Keyword.merge(
          [now: @now, env: %{"SELF_HOSTED" => "false"}],
          opts
        )
      )
end
