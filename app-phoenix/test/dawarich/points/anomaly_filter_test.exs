defmodule Dawarich.Points.AnomalyFilterTest do
  use Dawarich.JobsCase
  import Dawarich.AnomalyCase

  @base 1_704_067_200
  @home {13.405, 52.52}
  @far {23.405, 62.52}

  test "null island and absurd accuracy use strict thresholds and current user/range" do
    user = user!()
    other = user!()
    zero = point!(user, @base, {0, 0})
    absurd = point!(user, @base + 60, @home, accuracy: 10_001)

    for accuracy <- [nil, 101, 3_000, 10_000],
        do:
          point!(
            user,
            @base + 120 + Enum.find_index([nil, 101, 3_000, 10_000], &(&1 == accuracy)),
            @home,
            accuracy: accuracy
          )

    point!(user, @base - 1, @home, accuracy: 20_000)
    point!(other, @base, @home, accuracy: 20_000)
    assert filter(user, @base, @base + 600) == 2
    assert flagged(user) == [zero, absurd]
    assert flagged(other) == []

    assert [[true]] ==
             rows("SELECT updated_at > NOW()-interval '1 day' FROM points WHERE id=$1", [absurd])

    assert filter(user, @base, @base + 600) == 0
  end

  for value <- [false, 0, "0", "false", "f", "off", ""] do
    test "disabled Rails boolean #{inspect(value)} leaves flags and effects untouched" do
      user = user!(%{"gps_filtering_enabled" => unquote(value)})
      point!(user, @base, @home, accuracy: 20_000)
      assert filter(user, @base, @base + 1) == 0
      assert flagged(user) == []
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    end
  end

  for value <- [nil, true, 1, "true", "anything"] do
    test "enabled Rails boolean #{inspect(value)} filters" do
      user = user!(%{"gps_filtering_enabled" => unquote(value)})
      id = point!(user, @base, @home, accuracy: 20_000)
      assert filter(user, @base, @base + 1) == 1
      assert flagged(user) == [id]
    end
  end

  test "departed visits persist archival evidence, motion data wins, invalid and arrival dates survive" do
    user = user!()

    departed =
      point!(user, @base, @home,
        motion: %{"action" => "visit"},
        raw: %{"properties" => %{"departure_date" => "2026-05-19T18:34:25Z"}}
      )

    persisted =
      point!(user, @base + 1, @home,
        motion: %{"action" => "visit", "departure_date" => "2025-anything"},
        raw: %{}
      )

    for {date, i} <- Enum.with_index([nil, "4001-01-01", "junk", "3000-01-01"]),
        do:
          point!(user, @base + 2 + i, @home,
            motion: %{"action" => "visit", "departure_date" => date}
          )

    point!(user, @base + 7, @home,
      motion: %{"action" => "visit", "departure_date" => "4001-01-01"},
      raw: %{"properties" => %{"departure_date" => "2025-01-01"}}
    )

    assert filter(user, @base, @base + 10) == 2
    assert flagged(user) == [departed, persisted]

    assert [["2026-05-19T18:34:25Z"]] ==
             rows("SELECT motion_data->>'departure_date' FROM points WHERE id=$1", [departed])

    rows("UPDATE points SET raw_data='{}',anomaly=false WHERE id=$1", [departed])
    assert filter(user, @base, @base + 10) == 1
  end

  test "sentinel pass rejudges six hours, respects device/precision/anomaly and strict marker bounds" do
    user = user!()

    tower =
      point!(user, @base, @home,
        accuracy: 1500,
        velocity: "-1",
        vertical_accuracy: -1,
        tracker: "phone"
      )

    point!(user, @base + 300, @home, accuracy: 100, tracker: "phone")

    for {opts, i} <-
          Enum.with_index([
            [accuracy: 500, velocity: "-1", vertical_accuracy: -1],
            [accuracy: 1500, velocity: "0", vertical_accuracy: -1],
            [accuracy: 1500, velocity: "-1", vertical_accuracy: 0],
            [accuracy: 1500, velocity: "-1", vertical_accuracy: -1, tracker: "watch"]
          ]),
        do: point!(user, @base + 100 + i, @home, opts)

    assert filter(user, @base + 300, @base + 400) == 1
    assert flagged(user) == [tower]
  end

  test "coarse-only eras and already anomalous precision do not condemn sentinel" do
    user = user!()
    point!(user, @base, @home, accuracy: 1500, velocity: "-1", vertical_accuracy: -1)
    point!(user, @base + 60, @home, accuracy: 10, anomaly: true)
    assert filter(user, @base, @base + 100) == 0
    assert length(flagged(user)) == 1
  end

  test "spikes sharing timestamps use stable ids and independent device streams" do
    user = user!()
    other = point!(user, @base + 120, @home, tracker: "watch")
    spike = point!(user, @base + 120, @far, tracker: "phone")
    good = point!(user, @base + 120, {13.4051, 52.5201}, tracker: "phone")
    point!(user, @base, @home, tracker: "phone")
    point!(user, @base + 240, {13.4052, 52.5202}, tracker: "phone")
    assert filter(user, @base, @base + 300) == 1
    assert flagged(user) == [spike]
    refute other in flagged(user)
    refute good in flagged(user)
  end

  test "interleaved independent locations do not invent device travel" do
    user = user!()

    for i <- 0..4 do
      point!(user, @base + i * 60, @home, tracker: "phone")
      point!(user, @base + i * 60 + 1, @far, tracker: "watch")
    end

    assert filter(user, @base, @base + 600) == 0
  end

  test "brief displaced runs are removed shortest-first without surrounding fixes" do
    user = user!()
    point!(user, @base, @home)
    point!(user, @base + 60, {13.4051, 52.5201})

    run =
      for i <- 0..4,
          do: point!(user, @base + 120 + i * 60, {23.405 + i * 0.0001, 62.52 + i * 0.0001})

    point!(user, @base + 480, {13.4052, 52.5202})
    point!(user, @base + 540, {13.4053, 52.5203})
    assert filter(user, @base, @base + 600) == 5
    assert flagged(user) == run
  end

  test "long moving stays survive impossible boundary hops" do
    user = user!()
    point!(user, @base, @home)
    for i <- 0..11, do: point!(user, @base + 60 + i * 60, {4.35 + i * 0.0001, 50.85 + i * 0.0001})
    point!(user, @base + 900, @home)
    assert filter(user, @base, @base + 1000) == 0
  end

  for kind <- [:frozen, :remeasured, :moving, :too_long] do
    test "cached run #{kind} obeys extent accuracy span and recent-context rules" do
      user = user!()
      {last, expected} = cached_trace!(user, unquote(kind))
      assert filter(user, @base, last + 30) == length(expected)
      assert flagged(user) == expected
    end
  end

  test "single live batch rejudges complete recent frozen burst but not old bursts" do
    user = user!()
    live = {-118.4103, 33.9429}
    for i <- 0..2, do: point!(user, @base + i * 15, live)
    run = for i <- 0..7, do: point!(user, @base + 45 + i * 15, {-0.4803, 51.4693})
    for i <- 0..2, do: point!(user, @base + 180 + i * 15, live)
    assert filter(user, @base + 210, @base + 210) == 8
    assert flagged(user) == run
    rows("UPDATE points SET anomaly=false WHERE user_id=$1", [user])
    point!(user, @base + 20_000, live)
    assert filter(user, @base + 20_000, @base + 20_000) == 0
    assert flagged(user) == []
  end

  test "detour catches a stale fix with only one impossible leg" do
    user = user!()

    ids =
      trace!(user, [
        {@base, {12.247, 54.176}, []},
        {@base + 60, {12.247, 54.176}, []},
        {@base + 360, {13.517, 52.532}, []},
        {@base + 1260, {12.541, 54.392}, []},
        {@base + 1320, {12.541, 54.392}, []}
      ])

    assert filter(user, @base, @base + 1500) == 1
    assert flagged(user) == [Enum.at(ids, 2)]
  end

  test "ground-travel detour ceiling catches plausible single legs" do
    user = user!()

    ids =
      trace!(user, [
        {@base, {10.5526, 52.9697}, []},
        {@base + 480, {10.4417, 52.9117}, []},
        {@base + 2100, {12.3731, 51.3397}, []},
        {@base + 3000, {9.7419, 52.3775}, []},
        {@base + 3300, {9.7420, 52.3776}, []}
      ])

    assert filter(user, @base, @base + 3600) == 1
    assert flagged(user) == [Enum.at(ids, 2)]
  end

  test "a far stray interrupts one stay but a real multi-hour visit remains" do
    user = user!()
    point!(user, @base, {9.806, 52.310})
    stray = point!(user, @base + 45_540, {13.738, 51.050})
    point!(user, @base + 48_420, {9.806, 52.310})
    point!(user, @base + 48_480, {9.806, 52.310})
    assert filter(user, @base, @base + 90_000) == 1
    assert flagged(user) == [stray]
    other = user!()
    point!(other, @base, @home)
    for at <- [7200, 10_800, 14_400, 21_600], do: point!(other, @base + at, {11.576, 48.137})
    point!(other, @base + 36_000, @home)
    assert filter(other, @base, @base + 90_000) == 0
  end

  test "narrow windows only judge chosen ids plus defined recent lookback" do
    user = user!()
    point!(user, @base, @home)
    point!(user, @base + 60, @far)
    point!(user, @base + 120, @home)
    point!(user, @base + 10_000, @home)
    assert filter(user, @base + 10_000, @base + 10_000) == 0
    assert flagged(user) == []
  end

  test "window boundary context and month boundary still catch spikes" do
    user = user!()
    boundary = DateTime.to_unix(~U[2024-02-01 00:00:00Z])
    point!(user, boundary - 60, @home)
    spike = point!(user, boundary, @far)
    point!(user, boundary + 60, @home)
    assert filter(user, boundary, boundary) == 1
    assert flagged(user) == [spike]
  end

  test "fewer than three points skips speed SQL even when distant epochs overflow int32 subtraction" do
    user = user!()
    point!(user, -1_000_000_000, @home)
    point!(user, 1_700_000_000, @home)
    assert filter(user, 1_700_000_000, 1_700_000_000) == 0
    assert flagged(user) == []
  end

  test "signed point epoch boundary preserves Rails raw widened-context failure" do
    user = user!()
    assert_raise DBConnection.EncodeError, fn -> filter(user, -2_147_483_648, -2_147_483_648) end
  end

  test "null island includes the five kilometer neighborhood, not only exact zero" do
    user = user!()
    inside = point!(user, @base, {0.001, 0.001})
    point!(user, @base + 1, {0.1, 0.1})
    assert filter(user, @base, @base + 1) == 1
    assert flagged(user) == [inside]
  end

  test "no enclosing transaction silently changes pass partial commits" do
    user = user!()
    id = point!(user, @base, {0, 0})
    point!(user, @base + 60, @home, accuracy: 20_000)
    Process.put(:anomaly_writes, 0)

    fence = fn fun ->
      n = Process.get(:anomaly_writes)
      Process.put(:anomaly_writes, n + 1)
      if n == 1, do: raise(Dawarich.Imports.LeaseLost)
      fun.()
    end

    assert_raise Dawarich.Imports.LeaseLost, fn ->
      filter(user, @base, @base + 100, fence: fence)
    end

    assert flagged(user) == [id]
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  defp cached_trace!(user, kind) do
    live = {-118.4103, 33.9429}
    frozen = {-0.4803, 51.4693}

    for i <- 0..2,
        do: point!(user, @base + i * 15, {elem(live, 0) + i * 0.0001, elem(live, 1) + i * 0.0001})

    step = if kind == :too_long, do: 600, else: 15

    run =
      for i <- 0..7 do
        pos =
          if kind == :moving,
            do: {elem(frozen, 0) + i * 0.0009, elem(frozen, 1) + i * 0.0009},
            else: frozen

        point!(user, @base + 45 + i * step, pos,
          accuracy: if(kind == :remeasured, do: 10 + i, else: 10)
        )
      end

    last = @base + 60 + 7 * step

    for i <- 0..2,
        do:
          point!(
            user,
            last + i * 15,
            {elem(live, 0) + (i + 3) * 0.0001, elem(live, 1) + (i + 3) * 0.0001}
          )

    {last, if(kind == :frozen, do: run, else: [])}
  end
end
