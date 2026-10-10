defmodule Dawarich.Geocoding.PointFetchTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.{Config, PointFetch}

  @fixtures ~w(photon_komoot photon_selfhosted_key photon_chibigeo geoapify nominatim locationiq
               store_geodata_false country_alias_and_mismatch point_force_and_rerun)

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

  test "geodata floats from the provider are stored as Rails stores them" do
    f = load!("photon_komoot")
    [%{"url" => url, "status" => status, "body" => body} | _] = f["requests"]
    FakeHttp.stub(url, status, with_rails_rounding_cases(body))
    [%{"point_id" => id} | _] = f["calls"]

    PointFetch.run(ScratchRepo, id, Config.resolve(ScratchRepo, %{}), false)

    assert ScratchRepo.query!(
             "SELECT geodata->'properties'->>'extent', geodata->'properties'->>'distance' " <>
               "FROM points WHERE id = $1",
             [id]
           ).rows == [["[12.3731, 51.3398, 12.3732, 51.3397]", "1500.0"]]
  end

  test "a stale write repeats the lookup three times" do
    f = load!("store_geodata_false")
    stub_requests!(f["requests"])
    [%{"point_id" => id}] = f["calls"]

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "UPDATE points SET") do
        clear_response_cache!()

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

  test "a changed city marks the geocoded day in phoenix.stats_geocoded_days" do
    f = load!("photon_selfhosted_key")
    stub_requests!(f["requests"])
    config = Config.resolve(ScratchRepo, %{})
    [%{"point_id" => id}] = f["calls"]
    [user] = f["input"]["users"]
    member = "#{user["id"]}:2026-09-21"

    assert PointFetch.run(ScratchRepo, id, config, false) == :written

    [[version, due_at]] =
      ScratchRepo.query!(
        "SELECT version, due_at FROM phoenix.stats_geocoded_days WHERE member = $1",
        [member]
      ).rows

    assert_in_delta due_at, System.os_time(:second) + 3600, 5

    ScratchRepo.query!("UPDATE phoenix.stats_geocoded_days SET due_at = 0 WHERE member = $1", [
      member
    ])

    assert PointFetch.run(ScratchRepo, id, config, true) == :written

    assert ScratchRepo.query!(
             "SELECT version, due_at FROM phoenix.stats_geocoded_days WHERE member = $1",
             [member]
           ).rows == [[version, 0]]

    assert Enum.map(kinds(), & &1["kind"]) == ["points.tile_epoch", "points.tile_epoch"]
  end

  test "a geocoded-day write that fails is logged and the point stays written" do
    f = load!("photon_selfhosted_key")
    stub_requests!(f["requests"])
    [%{"point_id" => id}] = f["calls"]

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "INSERT INTO phoenix.stats_geocoded_days"),
        do: raise(Postgrex.Error, message: "queue unavailable")

      :ok
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert PointFetch.run(HookRepo, id, Config.resolve(ScratchRepo, %{}), false) == :written
      end)

    assert log =~ "event=geocoding.geocoded_day_failed user_id="
    assert geocoded_days() == []
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
end
