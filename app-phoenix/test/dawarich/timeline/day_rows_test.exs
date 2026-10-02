defmodule Dawarich.Timeline.DayRowsTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Timeline.DayRows

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    %{user: S.user!(7001)}
  end

  defp berlin(date, hours \\ 0),
    do: DateTime.to_unix(DateTime.new!(date, ~T[00:00:00], "Etc/UTC")) - 7200 + hours * 3600

  defp range(first, last), do: {berlin(first), berlin(last) + 86_399}

  defp utc(date, hours),
    do: NaiveDateTime.add(NaiveDateTime.new!(date, ~T[00:00:00]), hours * 3600 - 7200)

  defp fetch(user, first, last \\ nil, window_now \\ nil),
    do: DayRows.fetch(user, range(first, last || first), {first, last || first}, window_now)

  test "visits come in start order with Berlin ISO times; declined and deleted ones are left out",
       %{user: user} do
    d = ~D[2026-09-27]
    S.visit!(user.id, 7101, %{started_at: utc(d, 10), ended_at: utc(d, 11)})
    S.visit!(user.id, 7102, %{started_at: utc(d, 8), ended_at: utc(d, 9)})
    S.visit!(user.id, 7103, %{started_at: utc(d, 12), ended_at: utc(d, 13), status: 2})

    S.visit!(user.id, 7104, %{
      started_at: utc(d, 14),
      ended_at: utc(d, 15),
      deleted_at: utc(d, 16)
    })

    rows = fetch(user, d)

    assert Enum.map(rows.visits, & &1.id) == [7102, 7101]
    assert hd(rows.visits).started_at == "2026-09-27T08:00:00+02:00"
    assert hd(rows.visits).start_local == ~N[2026-09-27 08:00:00]
    assert hd(rows.visits).day == d
  end

  test "a track across local midnight carries each day's share of its span", %{user: user} do
    S.track!(user.id, 7201, %{start_at: utc(~D[2026-09-27], 22), end_at: utc(~D[2026-09-28], 2)})

    [track] = fetch(user, ~D[2026-09-27], ~D[2026-09-28]).tracks

    assert track.start_day == ~D[2026-09-27]
    assert track.shares == [{~D[2026-09-27], 0.5}, {~D[2026-09-28], 0.5}]
  end

  test "the 25-hour day of 2026-10-25 splits by real elapsed time", %{user: user} do
    S.track!(user.id, 7202, %{start_at: ~N[2026-10-24 21:00:00], end_at: ~N[2026-10-25 03:00:00]})

    [track] = fetch(user, ~D[2026-10-24], ~D[2026-10-25]).tracks

    assert track.shares == [{~D[2026-10-24], 1 / 6}, {~D[2026-10-25], 5 / 6}]
  end

  test "a track with no positive span counts wholly on its start day", %{user: user} do
    S.track!(user.id, 7203, %{start_at: utc(~D[2026-09-27], 9), end_at: utc(~D[2026-09-27], 9)})

    assert [%{shares: [{~D[2026-09-27], 1.0}]}] = fetch(user, ~D[2026-09-27]).tracks
  end

  test "a stationary track under 100 m is left out, one of 100 m stays", %{user: user} do
    d = ~D[2026-09-27]

    S.track!(user.id, 7204, %{
      start_at: utc(d, 9),
      end_at: utc(d, 10),
      dominant_mode: 1,
      distance: 99
    })

    S.track!(user.id, 7205, %{
      start_at: utc(d, 11),
      end_at: utc(d, 12),
      dominant_mode: 1,
      distance: 100
    })

    assert Enum.map(fetch(user, d).tracks, &{&1.id, &1.mode}) == [{7205, "stationary"}]
  end

  test "a restricted window drops what started before twelve months ago in the user's zone", %{
    user: user
  } do
    d = ~D[2025-09-29]
    S.visit!(user.id, 7105, %{started_at: utc(d, 11), ended_at: utc(d, 12)})
    S.visit!(user.id, 7106, %{started_at: utc(d, 13), ended_at: utc(d, 14)})
    S.track!(user.id, 7206, %{start_at: utc(d, 11), end_at: utc(d, 12)})

    rows = fetch(user, d, nil, ~U[2026-09-29 10:00:00Z])

    assert Enum.map(rows.visits, & &1.id) == [7106]
    assert rows.tracks == []
    assert Enum.map(fetch(user, d).visits, & &1.id) == [7105, 7106]
  end

  test "places fall back to latitude/longitude; tags follow tagging creation; suggestions follow place_visits",
       %{user: user} do
    d = ~D[2026-09-27]
    S.place!(user.id, 7301, "Café Kowalski", legacy: true)
    S.place!(user.id, 7302, "Clara-Zetkin-Park", offset: {-0.01, -0.005})
    S.tag!(user.id, 7401, "Work", 7301, ~N[2026-09-02 00:00:00])
    S.tag!(user.id, 7402, "Coffee", 7301, ~N[2026-09-01 00:00:00])

    S.visit!(user.id, 7107, %{
      started_at: utc(d, 9),
      ended_at: utc(d, 10),
      status: 0,
      place_id: 7301
    })

    S.suggest!(7501, 7107, 7302)

    rows = fetch(user, d)

    assert rows.places[7301].lat == 51.3397
    assert rows.places[7302].lng == 12.3731 - 0.01
    assert Enum.map(rows.tags[7301], & &1.name) == ["Coffee", "Work"]
    assert rows.suggestions == %{7107 => [7302]}
  end

  test "the number of statements does not grow with the number of visits", %{user: user} do
    d = ~D[2026-09-27]

    seed = fn ids ->
      for id <- ids do
        S.place!(user.id, id, "Place #{id}")
        S.tag!(user.id, id, "Tag #{id}", id, ~N[2026-09-01 00:00:00])

        S.visit!(user.id, id, %{
          started_at: utc(d, rem(id, 10) + 6),
          ended_at: utc(d, rem(id, 10) + 7),
          status: 0,
          place_id: id
        })

        S.suggest!(id, id, id)
        S.point!(user.id, id, berlin(d, rem(id, 10) + 6), %{visit_id: id})
      end
    end

    seed.([7601])
    {one, _} = queries(fn -> fetch(user, d) end)
    seed.([7602, 7603, 7604, 7605])
    {five, rows} = queries(fn -> fetch(user, d) end)

    assert length(rows.visits) == 5
    assert length(five) == length(one)
  end

  test "midnights mark the local start and last microsecond of each day, across 2026-10-25", %{
    user: user
  } do
    rows = fetch(user, ~D[2026-10-24], ~D[2026-10-26])
    {start, finish} = rows.midnights[~D[2026-10-25]]

    assert start == DateTime.to_unix(~U[2026-10-24 22:00:00Z]) * 1_000_000
    assert finish - start == 25 * 3_600_000_000 - 1
  end

  test "redetected follows visits_redetected_at", %{user: user} do
    legacy = S.user!(7002, %{"timezone" => "Europe/Berlin"}, %{visits_redetected_at: nil})

    assert fetch(user, ~D[2026-09-27]).redetected
    refute fetch(legacy, ~D[2026-09-27]).redetected
  end

  test "track/2 finds only the user's own track, with Rails' ISO start", %{user: user} do
    other = S.user!(7003)

    S.track!(user.id, 7207, %{
      start_at: utc(~D[2026-09-27], 7),
      end_at: utc(~D[2026-09-27], 8),
      dominant_mode: 4
    })

    S.track!(other.id, 7208, %{start_at: utc(~D[2026-09-27], 7), end_at: utc(~D[2026-09-27], 8)})

    assert %{id: 7207, mode: "cycling", started_at: "2026-09-27T07:00:00+02:00"} =
             DayRows.track(user, 7207)

    assert DayRows.track(user, 7208) == nil
  end

  defp queries(fun) do
    handler = "a6s2-day-rows-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == test_pid, do: send(test_pid, {:sql, meta.query})
      end,
      nil
    )

    try do
      result = fun.()
      {drain([]), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(acc) do
    receive do
      {:sql, sql} -> drain([sql | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
