defmodule Dawarich.Visits.StagesTest do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Visits.{
    CandidateLoader,
    DwellSweep,
    GapBridger,
    MovementReconciler,
    Runner,
    Settings,
    StayAssembler
  }

  for name <- Dawarich.VisitsCase.detection_fixture_names() do
    @name name

    test "each stage's output equals Rails' for every fixture: #{name}" do
      f = load_visits!(@name)
      stub_requests!(f["expected"]["requests"])
      uid = user_id(f)
      ctx = Runner.context(ScratchRepo, Settings.load(ScratchRepo, uid), f["run"]["time_zone"])
      assert Map.take(ctx.policy, policy_keys()) == atomize(f["policy"])

      {start, stop} = Runner.window(ctx, f["run"]["start_at"], f["run"]["end_at"])
      actual = ctx |> Runner.batches(start, stop) |> Enum.reduce(%{}, &stage(ctx, uid, &1, &2))

      expected_keys = expected_place_keys(f)

      for stage <- ~w(fragments bridged reconciled stays) do
        assert {stage, plain(actual[stage] || [])} == {stage, f["stages"][stage]}
      end

      assert attributed(actual["attributed"] || [], actual_place_keys()) ==
               attributed(f["stages"]["attributed"], expected_keys)
    end
  end

  test "a confident moving segment vetoes a fragment and snaps a neighbour's edges" do
    policy = Settings.policy(%{})

    frag =
      &%{start_ts: &1, end_ts: &2, center_lat: 51.3, center_lon: 12.3, count: 3, point_ids: [1]}

    seg = &%{mode: &1, confidence: &2, corrected: false, start_ts: &3, end_ts: &4}

    fragments = [frag.(1000, 2000), frag.(3000, 5000), frag.(9000, 9600)]

    segments = [
      seg.("driving", 0.9, 900, 2100),
      seg.("walking", nil, 2500, 3200),
      seg.("cycling", 0.2, 3000, 5000),
      seg.("stationary", 0.1, 4000, 4100),
      seg.("driving", 0.8, 4800, 6000),
      seg.("bus", 0.6, 8200, 8500)
    ]

    assert [a, b] = MovementReconciler.run(fragments, segments, policy)
    assert {a.start_ts, a.end_ts, a.corroborated} == {3200, 4800, true}
    assert {b.start_ts, b.end_ts, b.corroborated} == {8500, 9600, false}
  end

  test "segments come from the user's tracks that overlap the window, points skip anomalies and exact zeros" do
    Wave5bFixtures.load_input!(ScratchRepo, %{"users" => [%{"id" => 1}, %{"id" => 2}]})
    track = insert_track!(1)
    other = insert_track!(2)

    for {track_id, index, mode, confidence, corrected, from, to} <- [
          {track, 0, 5, 0.9, false, 2000, 3000},
          {track, 1, 1, nil, true, 500, 1500},
          {track, 2, 2, 0.4, false, 9500, 9800},
          {track, 3, 7, 0.9, false, 100, nil},
          {other, 0, 5, 0.9, false, 2000, 3000}
        ] do
      rows(
        "INSERT INTO track_segments (track_id, start_index, transportation_mode, confidence_score, corrected_at, " <>
          "start_at, end_at, created_at, updated_at) VALUES ($1, $2, $3, $4, CASE WHEN $5 THEN now() END, " <>
          "to_timestamp($6::bigint), to_timestamp($7::bigint), now(), now())",
        [track_id, index, mode, confidence, corrected, from, to]
      )
    end

    for {ts, wkt, anomaly} <- [
          {1100, "POINT(12.3731 51.3397)", nil},
          {1200, "POINT(12.3732 51.3398)", true},
          {1300, "POINT(0 0)", false},
          {1400, "POINT(0.001 0.001)", false},
          {9100, "POINT(12.3731 51.3397)", false}
        ] do
      rows(
        "INSERT INTO points (user_id, timestamp, lonlat, accuracy, anomaly, created_at, updated_at) " <>
          "VALUES (1, $1, ST_GeomFromText($2, 4326)::geography, 7, $3, now(), now())",
        [ts, wkt, anomaly]
      )
    end

    evidence = CandidateLoader.load(ScratchRepo, 1, 1000, 9000)

    assert evidence.segments == [
             %{mode: "stationary", confidence: nil, corrected: true, start_ts: 500, end_ts: 1500},
             %{mode: "driving", confidence: 0.9, corrected: false, start_ts: 2000, end_ts: 3000}
           ]

    assert Enum.map(evidence.points, &{&1.timestamp, &1.lat, &1.lon, &1.accuracy}) ==
             [{1100, 51.3397, 12.3731, 7}, {1400, 0.001, 0.001, 7}]
  end

  test "the 100,000-point candidate cap is honoured" do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(users  points  visits))
    Wave5bFixtures.load_input!(ScratchRepo, %{"users" => [%{"id" => 1}]})

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, accuracy, created_at, updated_at) " <>
        "SELECT 1, g, ST_SetSRID(ST_MakePoint(12.3731, 51.3397), 4326)::geography, 10, now(), now() " <>
        "FROM generate_series(1, 100_000) AS g",
      []
    )

    at_cap = CandidateLoader.load(ScratchRepo, 1, 0, 200_000)
    assert at_cap.skipped == false
    assert length(at_cap.points) == 100_000

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, accuracy, created_at, updated_at) VALUES " <>
        "(1, 100_001, ST_SetSRID(ST_MakePoint(12.3731, 51.3397), 4326)::geography, 10, now(), now())",
      []
    )

    over_cap = CandidateLoader.load(ScratchRepo, 1, 0, 200_000)
    assert over_cap.skipped == true
    assert over_cap.points == []
    assert over_cap.segments == []
  end

  test "the window widens to overlapping machine visits only" do
    f = load_visits!("detection_pipeline")
    uid = user_id(f)
    ctx = Runner.context(ScratchRepo, Settings.load(ScratchRepo, uid), "UTC")
    {start, stop} = {f["run"]["start_at"], f["run"]["end_at"]}

    for {from, to, status} <- [
          {start - 7200, start + 600, 0},
          {stop - 60, stop + 3600, 0},
          {start - 99_999, start, 1}
        ] do
      rows(
        "INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at) " <>
          "VALUES ($1, to_timestamp($2::bigint) AT TIME ZONE 'UTC', to_timestamp($3::bigint) AT TIME ZONE 'UTC', " <>
          "1, 'Existing', $4, now(), now())",
        [uid, from, to, status]
      )
    end

    assert Runner.window(ctx, start, stop) == {start - 7200, stop + 3600}
  end

  defp insert_track!(user_id) do
    [[id]] =
      rows(
        "INSERT INTO tracks (user_id, start_at, end_at, original_path, created_at, updated_at) VALUES " <>
          "($1, now(), now(), ST_GeomFromText('LINESTRING(12.37 51.33, 12.38 51.34)', 4326), now(), now()) RETURNING id",
        [user_id]
      )

    id
  end

  defp stage(ctx, uid, [bs, be], acc) do
    evidence = CandidateLoader.load(ScratchRepo, uid, bs, be)
    by_id = Map.new(evidence.points, &{&1.id, &1})
    policy = ctx.policy

    {acc, stays} =
      if evidence.points == [] do
        {acc, []}
      else
        fragments = DwellSweep.run(evidence.points, policy)
        bridged = GapBridger.run(fragments, policy)
        reconciled = MovementReconciler.run(bridged, evidence.segments, policy)
        stays = StayAssembler.run(reconciled, by_id, policy)

        acc =
          Enum.reduce(
            [
              {"fragments", fragments},
              {"bridged", bridged},
              {"reconciled", reconciled},
              {"stays", stays}
            ],
            acc,
            fn {k, v}, a -> Map.update(a, k, [v], &(&1 ++ [v])) end
          )

        {acc, stays}
      end

    scored = if stays == [], do: [], else: Runner.attribute_and_score(ctx, stays, by_id)
    Map.update(acc, "attributed", [scored], &(&1 ++ [scored]))
  end

  defp attributed(batches, place_key) do
    for batch <- batches do
      for stay <- batch do
        stay = plain(stay)

        stay
        |> Map.update!("place", &Map.fetch!(place_key, &1))
        |> Map.update!("evidence", &to_string/1)
        |> Map.update!("confidence_breakdown", &Map.new/1)
      end
    end
  end

  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)

  defp plain(%{} = map),
    do:
      Map.new(map, fn
        {k, v} when is_atom(k) and k != nil -> {Atom.to_string(k), plain_value(k, v)}
        {k, v} -> {k, v}
      end)

  defp plain_value(:evidence, v), do: to_string(v)
  defp plain_value(:confidence_breakdown, v), do: Map.new(v)
  defp plain_value(_k, v), do: v

  defp policy_keys,
    do: [:stay_radius_m, :min_dwell_s, :min_points, :merge_gap_s, :suggestions_enabled]

  defp atomize(map), do: Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
end
