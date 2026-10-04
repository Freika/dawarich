defmodule Dawarich.Visits.DetectionTest do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Visits.{HistoryRedetect, Settings, SmartDetect}

  for name <- Dawarich.VisitsCase.detection_fixture_names() do
    @name name

    test "every visits fixture writes Rails' rows and effects: #{name}" do
      f = load_visits!(@name)
      result = detect!(f)
      assert_matches_rails!(f, f["expected"], result)
    end
  end

  test "an area outranks a known manual place at the same spot" do
    f = load_visits!("attribution_detection")
    uid = user_id(f)

    rows(
      "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, created_at, updated_at) VALUES " <>
        "($1, 'Decoy', 51.3397, 12.3731, ST_GeomFromText('POINT(12.3731 51.3397)', 4326)::geography, 0, now(), now())",
      [uid]
    )

    detect!(f)

    assert comparable_visits(visits(uid), actual_place_keys()) ==
             comparable_visits(f["expected"]["visits"], expected_place_keys(f))
  end

  test "plan_restricted clamps the start to twelve months ago in the payload's zone" do
    for restricted <- [true, false] do
      Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(users  points  visits))

      Wave5bFixtures.load_input!(ScratchRepo, %{"users" => [%{"id" => 1}]})
      uid = 1
      now = System.os_time(:second)
      old_ts = now - 400 * 86_400
      recent_ts = now - 86_400

      for base <- [old_ts, recent_ts], i <- 0..5 do
        rows(
          "INSERT INTO points (user_id, timestamp, lonlat, accuracy, created_at, updated_at) VALUES " <>
            "($1, $2, ST_GeomFromText('POINT(12.3731 51.3397)', 4326)::geography, 10, now(), now())",
          [uid, base + i * 600]
        )
      end

      args = %{"time_zone" => "Europe/Berlin", "plan_restricted" => restricted}
      SmartDetect.run(ScratchRepo, uid, old_ts - 10_000, recent_ts + 7200, args)
      started = for v <- visits(uid), do: v["started_at"]

      assert started == if(restricted, do: [recent_ts], else: [old_ts, recent_ts])
    end
  end

  test "the history purge wipes out-of-range machine visits only, with their effects" do
    for table <- ~w(places visits) do
      rows("SELECT setval(pg_get_serial_sequence($1,'id'),1,false)", [table])
    end

    f = load_visits!("detection_pipeline")
    uid = user_id(f)

    rows(
      "INSERT INTO places (user_id, name, latitude, longitude, source, created_at, updated_at) " <>
        "VALUES ($1, 'P', 1, 1, 1, now(), now()), ($1, 'Q', 1, 1, 1, now(), now())",
      [uid]
    )

    for {from, place, status} <- [
          {1_780_000_000, 1, 0},
          {1_790_000_000, nil, 0},
          {1_770_000_000, nil, 1}
        ] do
      rows(
        "INSERT INTO visits (user_id, place_id, started_at, ended_at, duration, name, status, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, $4, 10, 'V', $5, now(), now())",
        [uid, place, epoch(from), epoch(from + 600), status]
      )
    end

    rows(
      "INSERT INTO place_visits (place_id, visit_id, created_at, updated_at) VALUES (2, 1, now(), now())",
      []
    )

    rows("UPDATE points SET visit_id = 1 WHERE user_id = $1", [uid])

    assert HistoryRedetect.purge(ScratchRepo, uid, 1_789_000_000, 1_791_000_000) == 1
    assert for(v <- visits(uid), do: v["id"]) == [3, 2]
    assert rows("SELECT count(*) FROM points WHERE visit_id IS NOT NULL", []) == [[0]]
    assert rows("SELECT count(*) FROM place_visits", []) == [[0]]
    assert effects(actual_place_keys())["orphan_place_ids"] == [1, 2]
    assert effects(actual_place_keys())["visit_months"] == ["2026-05"]

    assert HistoryRedetect.purge(ScratchRepo, uid, nil, nil) == 1
    assert for(v <- visits(uid), do: v["id"]) == [3]
  end

  test "an unchanged re-run writes nothing" do
    f = load_visits!("unchanged_rerun")
    detect!(f)
    ids = Enum.map(visits(user_id(f)), & &1["id"])
    commands = rails_commands_count()

    result = detect!(f)

    assert Enum.map(visits(user_id(f)), & &1["id"]) == ids
    assert rails_commands_count() == commands
    assert length(result.visits) == f["rerun"]["returned"]

    assert comparable_visits(visits(user_id(f)), actual_place_keys()) ==
             comparable_visits(f["rerun"]["visits"], expected_place_keys(f))
  end

  test "a NULL-attachable note makes no visit machine-detected" do
    f = load_visits!("null_attachable_note")
    [existing] = visits(user_id(f))

    detect!(f)

    assert existing in visits(user_id(f))

    started =
      for %{"kind" => "visit_months_changed", "payload" => p} <- kinds(), do: p["started_at"]

    assert length(started) == 1
    assert length(hd(started)) == 2
    refute Enum.any?(kinds(), &(&1["kind"] == "places_delete_if_orphan"))
  end

  test "a unique collision drops one stay" do
    f = load_visits!("suggest_geocoding_disabled")
    uid = user_id(f)
    fresh_place_id = Enum.find(f["input"]["places"], &(&1["name"] == "Fresh Place"))["id"]
    :persistent_term.put({__MODULE__, :collided}, false)
    on_exit(fn -> :persistent_term.erase({__MODULE__, :collided}) end)

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "INSERT INTO visits") and
           not :persistent_term.get({__MODULE__, :collided}) do
        :persistent_term.put({__MODULE__, :collided}, true)

        ScratchRepo.query!(
          "INSERT INTO visits (user_id, place_id, started_at, ended_at, duration, name, status, demo, " <>
            "created_at, updated_at) VALUES ($1, $2, $3, $4, 10, 'Collider', 1, false, now(), now())",
          [uid, fresh_place_id, epoch(1_790_010_800), epoch(1_790_011_400)]
        )
      end
    end)

    result = SmartDetect.run(HookRepo, uid, f["run"]["start_at"], f["run"]["end_at"], run_args(f))

    assert length(result.visits) == 1

    assert for(v <- visits(uid), do: {v["started_at"], v["name"], v["status"]}) ==
             [{1_790_000_000, "Covered Place", 0}, {1_790_010_800, "Collider", 1}]

    claims = point_claims(uid)
    assert Enum.take(claims, 6) == Enum.take(f["expected"]["point_claims"], 6)
    assert Enum.all?(Enum.drop(claims, 6), fn [_ts, visit] -> visit == nil end)
  end

  test "a legacy visit is rescored from its own points like Rails" do
    f = load_visits!("legacy_confidence_backfill")
    uid = user_id(f)

    HistoryRedetect.backfill(
      ScratchRepo,
      uid,
      Settings.policy(hd(f["input"]["users"])["settings"])
    )

    assert visits(uid) == f["expected"]["visits"]
  end

  test "stitching bridges a silent gap across the batch edge and never over an anchor" do
    edge = 1_790_805_600
    args = %{"time_zone" => "Europe/Berlin", "plan_restricted" => false}

    for anchored <- [false, true] do
      Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(users  points  visits))

      Wave5bFixtures.load_input!(ScratchRepo, %{"users" => [%{"id" => 7}]})

      for {offset, i} <- Enum.with_index([-3600, -3000, -2400, -1800, 600, 1200, 1800, 2400]) do
        rows(
          "INSERT INTO points (user_id, timestamp, lonlat, accuracy, created_at, updated_at) VALUES " <>
            "(7, $1, ST_SetSRID(ST_MakePoint(12.3731 + $2::float8, 51.3397 + $2::float8), 4326)::geography, 10, " <>
            "now(), now())",
          [edge + offset, i * 0.00001]
        )
      end

      if anchored,
        do:
          rows(
            "INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at) " <>
              "VALUES (7, $1, $2, 10, 'Anchor', 1, now(), now())",
            [epoch(edge - 1200), epoch(edge - 600)]
          )

      result = SmartDetect.run(ScratchRepo, 7, edge - 30 * 86_400, edge + 9 * 86_400, args)
      machine = for v <- visits(7), v["status"] == 0, do: {v["started_at"], v["ended_at"]}

      if anchored do
        assert machine == [{edge - 3600, edge - 1800}, {edge + 600, edge + 2400}]
        assert length(result.visits) == 2
      else
        assert machine == [{edge - 3600, edge + 2400}]
        assert [%{started_at: s, ended_at: e}] = result.visits
        assert {s, e} == {edge - 3600, edge + 2400}
        assert Enum.uniq(for [_ts, started] <- point_claims(7), do: started) == [edge - 3600]
      end
    end
  end

  defp detect!(f) do
    stub_requests!(f["expected"]["requests"])

    SmartDetect.run(
      ScratchRepo,
      user_id(f),
      f["run"]["start_at"],
      f["run"]["end_at"],
      run_args(f)
    )
  end

  defp assert_matches_rails!(f, expected, result) do
    uid = user_id(f)
    actual_key = actual_place_keys()
    expected_key = expected_place_keys(f)

    assert length(result.visits) == expected["returned"]

    assert comparable_visits(visits(uid), actual_key) ==
             comparable_visits(expected["visits"], expected_key)

    assert point_claims(uid) == expected["point_claims"]
    assert Enum.sort(places(uid)) == Enum.sort(expected_places(expected["places"]))
    assert tags(uid) == expected_tags(expected["tags"])
    assert FakeHttp.requests() == Enum.map(expected["requests"], & &1["url"])

    actual_effects = effects(actual_key)
    expected_effects = expected_effects(expected["effects"], expected_key)

    if f["run"]["via"] == "suggest" do
      assert actual_effects["reverse_geocode_place_ids"] == []

      assert Map.delete(actual_effects, "reverse_geocode_place_ids") ==
               Map.delete(expected_effects, "reverse_geocode_place_ids")
    else
      assert actual_effects == expected_effects
    end
  end

  defp epoch(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_naive()
end
