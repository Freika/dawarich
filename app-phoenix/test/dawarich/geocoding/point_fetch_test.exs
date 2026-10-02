defmodule Dawarich.Geocoding.PointFetchTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.{Config, PointFetch}
  alias Dawarich.Redis

  @fixtures ~w(photon_komoot photon_selfhosted_key photon_chibigeo geoapify nominatim locationiq
               store_geodata_false country_alias_and_mismatch point_force_and_rerun)
  @pending "stats:geocoded_days:pending"

  for name <- @fixtures do
    @name name

    test "every point fixture stores Rails' row, text for text: #{name}" do
      f = load!(@name)
      stub_requests!(f["requests"])
      config = Config.resolve(ScratchRepo, %{})
      assert comparable(config) == f["config"]

      for call <- f["calls"] do
        clear_limiter!()
        PointFetch.run(ScratchRepo, call["point_id"], config, call["force"])
      end

      assert points() == expected_points(f["expected"]["points"])
      assert kinds() == f["expected"]["effects"]["kinds"]
      assert geocoded_days() == Enum.sort(f["expected"]["effects"]["geocoded_days"])
      assert FakeHttp.requests() == Enum.map(f["requests"], & &1["url"])
      assert cache_entries() == Enum.sort_by(f["cache"], & &1["key"])
    end
  end

  test "a stale write repeats the lookup three times" do
    f = load!("store_geodata_false")
    stub_requests!(f["requests"])
    [%{"point_id" => id}] = f["calls"]

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "UPDATE points SET") do
        {:ok, "OK"} = Redis.cache_command(["FLUSHDB"])

        Task.await(
          Task.async(fn ->
            ScratchRepo.query!(
              "UPDATE points SET lock_version = lock_version + 1 WHERE id = $1",
              [id]
            )
          end)
        )
      end

      :ok
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert PointFetch.run(HookRepo, id, Config.resolve(ScratchRepo, %{}), false) == :stale
      end)

    assert log =~ "event=geocoding.point_stale point_id=#{id}"
    assert length(FakeHttp.requests()) == 4
    assert [[^id, nil, nil, nil, "{}", false, 4]] = points()
    assert kinds() == []
    assert geocoded_days() == []
  end

  test "force and non-force" do
    f = load!("point_force_and_rerun")
    stub_requests!(f["requests"])
    config = Config.resolve(ScratchRepo, %{})
    [%{"point_id" => id} | _] = f["calls"]

    assert PointFetch.run(ScratchRepo, id, config, false) == :skipped
    assert FakeHttp.requests() == []

    assert PointFetch.run(ScratchRepo, id, config, true) == :written
    assert length(FakeHttp.requests()) == 1
    assert [[^id, "Leipzig", "Germany", nil, _geodata, true, 1]] = points()
  end

  test "a changed city marks the geocoded day in Sidekiq's Redis" do
    f = load!("photon_selfhosted_key")
    stub_requests!(f["requests"])
    config = Config.resolve(ScratchRepo, %{})
    [%{"point_id" => id}] = f["calls"]
    [user] = f["input"]["users"]
    member = "#{user["id"]}:2026-09-21"
    sidekiq = sidekiq_redis()

    assert PointFetch.run(ScratchRepo, id, config, false) == :written

    {:ok, score} = Redix.command(sidekiq, ["ZSCORE", @pending, member])
    assert_in_delta String.to_integer(score), System.os_time(:second) + 3600, 5
    {:ok, version} = Redix.command(sidekiq, ["GET", "stats:geocoded_days:version:" <> member])
    assert is_binary(version)

    Redix.command!(sidekiq, ["ZREM", @pending, member])
    assert PointFetch.run(ScratchRepo, id, config, true) == :written

    assert Redix.command(sidekiq, ["ZSCORE", @pending, member]) == {:ok, nil}

    assert Redix.command(sidekiq, ["GET", "stats:geocoded_days:version:" <> member]) ==
             {:ok, version}

    assert Enum.map(kinds(), & &1["kind"]) == ["points.tile_epoch", "points.tile_epoch"]
  end

  test "a missing point is :missing" do
    config = config_from(fixture("photon_selfhosted_key")["config"])

    ExUnit.CaptureLog.capture_log(fn ->
      assert PointFetch.run(ScratchRepo, 424_242, config, true) == :missing
    end)

    assert FakeHttp.requests() == []
  end

  test "an error document writes nothing; a provider error is logged without a write" do
    f = load!("nominatim")
    stub_requests!(f["requests"])
    [first, second] = f["requests"]
    FakeHttp.stub(first["url"], 200, ~s({"error":"Unable to geocode"}))
    config = Config.resolve(ScratchRepo, %{})
    [%{"point_id" => errored}, %{"point_id" => limited}] = f["calls"]

    assert PointFetch.run(ScratchRepo, errored, config, false) == :skipped

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert PointFetch.run(ScratchRepo, limited, config, false) == :error
      end)

    assert log =~
             "event=geocoding.point_provider_error point_id=#{limited} class=over_query_limit"

    refute log =~ second["body"]
    assert kinds() == []
    assert [[_, nil, nil, nil, "{}", false, 0], [_, nil, nil, nil, "{}", false, 0]] = points()
  end

  defp sidekiq_redis do
    config = Application.fetch_env!(:dawarich, :redis)
    {:ok, conn} = Redix.start_link(config[:url], database: 1)
    on_exit(fn -> Process.alive?(conn) && Redix.stop(conn) end)
    conn
  end
end
