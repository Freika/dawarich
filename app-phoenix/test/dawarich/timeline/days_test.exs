defmodule Dawarich.Timeline.DaysTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Timeline.Days

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    %{user: S.user!(7011)}
  end

  defp utc(date, hours, minutes \\ 0),
    do:
      NaiveDateTime.add(
        NaiveDateTime.new!(date, ~T[00:00:00]),
        hours * 3600 + minutes * 60 - 7200
      )

  defp window(first, last) do
    last = last || first

    %{
      start: Date.to_iso8601(first) <> "T00:00:00+02:00",
      end: Date.to_iso8601(last) <> "T23:59:59+02:00",
      start_date: first,
      end_date: last
    }
  end

  defp days(user, first, last \\ nil), do: Days.load(user, window(first, last), nil).days

  test "interleaves visits and tracks chronologically (:53) and counts per status (:531)", %{
    user: user
  } do
    d = ~D[2026-09-27]
    S.place!(user.id, 7311, "Bibliotheca Albertina")

    S.visit!(user.id, 7111, %{
      started_at: utc(d, 9),
      ended_at: utc(d, 10),
      place_id: 7311,
      duration: 60
    })

    S.visit!(user.id, 7112, %{
      started_at: utc(d, 12),
      ended_at: utc(d, 13),
      status: 0,
      duration: 60
    })

    S.track!(user.id, 7211, %{
      start_at: utc(d, 10, 15),
      end_at: utc(d, 11),
      distance: 2400,
      duration: 2700
    })

    [day] = days(user, d)

    assert Enum.map(day.entries, &(&1[:visit_id] || &1[:track_id])) == [7111, 7211, 7112]
    assert day.summary.confirmed_count == 1
    assert day.summary.suggested_count == 1
    assert day.summary.places_visited == 1
    assert day.summary.time_stationary_minutes == 120
    assert day.summary.time_moving_minutes == 45
    assert day.summary.total_distance == 2.4
  end

  test "bounds span the visit places and the day's track extent (:103)", %{user: user} do
    d = ~D[2026-09-27]
    S.place!(user.id, 7312, "Völkerschlachtdenkmal", offset: {0.05, -0.02})
    S.visit!(user.id, 7113, %{started_at: utc(d, 9), ended_at: utc(d, 10), place_id: 7312})
    S.track!(user.id, 7212, %{start_at: utc(d, 11), end_at: utc(d, 12)})

    [[min_lng, _min_lat, _max_lng, max_lat]] =
      Dawarich.Repo.query!(
        "SELECT ST_XMin(e), ST_YMin(e), ST_XMax(e), ST_YMax(e) FROM " <>
          "(SELECT ST_Extent(original_path::geometry) AS e FROM tracks WHERE id = 7212) x"
      ).rows

    [day] = days(user, d)

    assert day.bounds == %{
             sw_lat: 51.3397 - 0.02,
             sw_lng: min_lng,
             ne_lat: max_lat,
             ne_lng: 12.3731 + 0.05
           }
  end

  test "confident per-mode distances, largest first, chips under 0.5 dropped (:173)", %{
    user: user
  } do
    d = ~D[2026-09-27]
    S.track!(user.id, 7213, %{start_at: utc(d, 9), end_at: utc(d, 10), distance: 5000})

    S.segment!(7213, 7501, %{
      transportation_mode: 2,
      distance: 1800,
      duration: 1500,
      confidence_score: 0.9
    })

    S.segment!(7213, 7502, %{transportation_mode: 4, distance: 3000, duration: 900})

    S.segment!(7213, 7503, %{
      transportation_mode: 5,
      distance: 900,
      duration: 120,
      confidence_score: 0.4
    })

    S.segment!(7213, 7504, %{
      transportation_mode: 7,
      distance: 400,
      duration: 60,
      confidence_score: 0.2,
      corrected_at: utc(d, 12)
    })

    [day] = days(user, d)

    assert day.summary.mode_distances == [{"cycling", 3.0}, {"walking", 1.8}]
    assert hd(day.entries).moving_duration == 2580
  end

  test "a track over midnight is a continuation on the second day, scaled by its share (:142, :203)",
       %{user: user} do
    S.track!(user.id, 7214, %{
      start_at: utc(~D[2026-09-27], 22),
      end_at: utc(~D[2026-09-28], 2),
      distance: 60_000,
      duration: 14_400,
      dominant_mode: 5
    })

    S.segment!(7214, 7505, %{
      transportation_mode: 5,
      distance: 58_000,
      duration: 9000,
      confidence_score: 0.95
    })

    [first, second] = days(user, ~D[2026-09-27], ~D[2026-09-28])
    [cont] = second.entries

    assert first.date == "2026-09-27" and hd(first.entries).continuation_of_date == nil
    assert cont.continuation_of_date == "2026-09-27"
    assert {cont.day_distance, cont.day_duration, cont.moving_duration} == {30.0, 7200, 4500}
    assert second.summary.total_distance == 30.0
    assert second.bounds == nil
  end

  test "a continuation sorts by its clamped end, after the day's earlier rows", %{user: user} do
    S.track!(user.id, 7215, %{start_at: utc(~D[2026-09-27], 23), end_at: utc(~D[2026-09-28], 9)})

    S.visit!(user.id, 7114, %{
      started_at: utc(~D[2026-09-28], 6),
      ended_at: utc(~D[2026-09-28], 7)
    })

    [_, second] = days(user, ~D[2026-09-27], ~D[2026-09-28])

    assert Enum.map(second.entries, &(&1[:visit_id] || &1[:track_id])) == [7114, 7215]
  end

  test "suggested places: the visit's place first, duplicates by normalized name dropped (:340, :346, :1033)",
       %{user: user} do
    d = ~D[2026-09-27]
    S.place!(user.id, 7313, "Bäckerei Kleinert")
    S.place!(user.id, 7314, " bäckerei kleinert ")
    S.place!(user.id, 7315, "Clara-Zetkin-Park")

    S.visit!(user.id, 7115, %{
      started_at: utc(d, 9),
      ended_at: utc(d, 10),
      status: 0,
      place_id: 7313,
      confidence: 55
    })

    S.suggest!(7601, 7115, 7314)
    S.suggest!(7602, 7115, 7315)

    S.visit!(user.id, 7116, %{
      started_at: utc(d, 11),
      ended_at: utc(d, 12),
      place_id: 7315,
      confidence: 80
    })

    [day] = days(user, d)
    [suggested, confirmed] = day.entries

    assert Enum.map(suggested.suggested_places, & &1.id) == [7313, 7315]
    assert suggested.confidence_band == "medium"
    refute Map.has_key?(confirmed, :suggested_places)
    assert confirmed.confidence_band == "high"
  end

  test "groups by the user's zone: 23:30 UTC is the next day in Tokyo (:823)" do
    tokyo = S.user!(7012, %{"timezone" => "Asia/Tokyo"})

    S.visit!(tokyo.id, 7117, %{
      started_at: ~N[2026-01-15 23:30:00],
      ended_at: ~N[2026-01-16 01:00:00]
    })

    window = %{
      start: "2026-01-16T00:00:00+09:00",
      end: "2026-01-16T23:59:59+09:00",
      start_date: ~D[2026-01-16],
      end_date: ~D[2026-01-16]
    }

    assert [%{date: "2026-01-16", entries: [%{started_at: "2026-01-16T08:30:00+09:00"}]}] =
             Days.load(tokyo, window, nil).days
  end

  test "miles convert distance and speed (:855)" do
    mi = S.user!(7013, %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "mi"}})
    d = ~D[2026-09-27]

    S.track!(mi.id, 7216, %{
      start_at: utc(d, 9),
      end_at: utc(d, 10),
      distance: 16_093,
      avg_speed: 32.2
    })

    [%{entries: [journey]}] = days(mi, d)

    assert {journey.distance, journey.distance_unit, journey.avg_speed, journey.speed_unit} ==
             {10.0, "mi", 20.0, "mph"}
  end

  test "stationary tracks count no moving minutes (:984)", %{user: user} do
    d = ~D[2026-09-27]

    S.track!(user.id, 7217, %{
      start_at: utc(d, 9),
      end_at: utc(d, 10),
      dominant_mode: 1,
      distance: 150,
      duration: 3600
    })

    assert [%{summary: %{time_moving_minutes: 0}}] = days(user, d)
  end

  test "a window longer than 31 days is empty; exactly 31 days is not (MAX_RANGE)", %{user: user} do
    S.visit!(user.id, 7118, %{
      started_at: utc(~D[2026-09-10], 9),
      ended_at: utc(~D[2026-09-10], 10)
    })

    long = %{
      start: "2026-08-27T00:00:00+02:00",
      end: "2026-09-27T00:00:01+02:00",
      start_date: ~D[2026-08-27],
      end_date: ~D[2026-09-27]
    }

    exact = %{long | end: "2026-09-27T00:00:00+02:00"}

    assert Days.load(user, long, nil).days == []
    assert [_] = Days.load(user, exact, nil).days
  end

  test "rows outside the window's local dates are left out", %{user: user} do
    S.track!(user.id, 7218, %{start_at: utc(~D[2026-09-26], 22), end_at: utc(~D[2026-09-27], 1)})

    assert [%{date: "2026-09-27", entries: [%{continuation_of_date: "2026-09-26"}]}] =
             days(user, ~D[2026-09-27])
  end
end
