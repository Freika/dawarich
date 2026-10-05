defmodule Dawarich.ReleaseOperations.RecalculationZoneTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.ReleaseJobs
  alias Dawarich.ReleaseOperations, as: Ops

  @now ~U[2026-10-03 12:00:00Z]
  @done "anomaly_rules_recalculated_at"

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_release_zone
      )

    ScratchRepo.put_dynamic_repo(pool)
    previous = System.get_env("TIME_ZONE")

    on_exit(fn ->
      ScratchRepo.put_dynamic_repo(ScratchRepo)
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    start_oban(:release_zone)
    :ok
  end

  test "decoded release operations preserve Rails ambient stamps and boundary repairs through successors" do
    for {configured, zone} <- [
          {nil, "Europe/Berlin"},
          {"Europe/Berlin", "Europe/Berlin"},
          {"Tokyo", "Asia/Tokyo"}
        ] do
      if configured,
        do: System.put_env("TIME_ZONE", configured),
        else: System.delete_env("TIME_ZONE")

      source = Enum.find(Fixtures.corpus()["release_zones"], &(&1["zone"] == zone))
      reset!(ScratchRepo)
      Fixtures.load!(ScratchRepo, source["fleet"])
      rows("UPDATE users SET settings=settings || $1", [%{"gps_filtering_enabled" => true}])

      assert {:ok, worker, args} =
               ReleaseJobs.decode("DataMigrations::RecalculateAnomaliesJob", [])

      assert args["cursor"]["request"]["ambient_zone"] == zone
      assert run(worker, args) == :ok
      [[child]] = rows("SELECT args FROM oban.oban_jobs")
      assert child["cursor"]["request"]["ambient_zone"] == zone
      rows("DELETE FROM oban.oban_jobs")
      hold_lease!(ScratchRepo, "anomaly_backfill:170101", "other")
      assert run(Ops.AnomaliesUser, child, lease: [timeout_ms: 0]) == :ok
      [[retry]] = rows("SELECT args FROM oban.oban_jobs")
      assert retry["cursor"]["request"]["ambient_zone"] == zone
      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.leases WHERE holder='other'")
      rows("UPDATE users SET settings=settings || $1", [%{"gps_filtering_enabled" => "off"}])
      assert run(Ops.AnomaliesUser, retry) == :ok
      expected = hd(source["fleet"]["expected"]["rows"]["users"])["settings"][@done]
      assert rows("SELECT settings->>$1 FROM users", [@done]) == [[expected]]
      [[slot]] = rows("SELECT args FROM oban.oban_jobs")
      assert slot["cursor"]["request"]["ambient_zone"] == zone

      reset!(ScratchRepo)
      tracker = source["tracker"]
      Fixtures.load!(ScratchRepo, tracker)
      dir = Path.join(System.tmp_dir!(), "release-zone-#{Ecto.UUID.generate()}")
      File.mkdir_p!(Path.join([dir, "storage", "a1", "2d"]))
      File.mkdir_p!(Path.join(dir, "tmp"))

      File.write!(
        Path.join([dir, "storage", "a1", "2d", "a12d1b3-records-source"]),
        tracker["records"]
      )

      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, worker, args} =
               ReleaseJobs.decode("DataMigrations::RecalculatePerTrackerTracksJob", [])

      assert args["cursor"]["request"]["ambient_zone"] == zone
      assert run(worker, args, rand: fn _ -> 0 end) == :ok
      [[child]] = rows("SELECT args FROM oban.oban_jobs")
      assert child["cursor"]["request"]["ambient_zone"] == zone

      opts = [
        services: %{
          "test" => %{service: "local", stored_service: "test", root: Path.join(dir, "storage")}
        },
        download_opts: [temp_dir: Path.join(dir, "tmp")],
        after_repair: fn devices, _ -> assert devices == tracker["count"] end
      ]

      assert run(worker, child, opts) == :ok

      assert rows("SELECT timestamp,tracker_id FROM points") == [
               [tracker["timestamp"], tracker["tracker_id"]]
             ]

      assert File.ls!(Path.join(dir, "tmp")) == []
    end
  end

  defp run(worker, args, opts \\ []) do
    Ops.run(
      ScratchRepo,
      :release_zone,
      worker,
      %Oban.Job{args: args, attempt: 1, max_attempts: 26},
      Keyword.merge([now: @now, env: %{"SELF_HOSTED" => "false"}, jitter_draw: 0.0], opts)
    )
  end
end
