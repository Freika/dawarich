defmodule DawarichWeb.TimelineFormatTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.{LocalizedDate, TimelineFormat}

  defp entry(start_s, end_s, extra \\ %{}),
    do:
      Map.merge(
        %{
          type: "visit",
          start_s: start_s,
          end_s: end_s,
          end_local: NaiveDateTime.from_gregorian_seconds(end_s + 62_167_219_200)
        },
        extra
      )

  test "with_gaps marks interior holes of 45 minutes after re-detection and 90 before" do
    rows = [entry(0, 3600), entry(3600 + 45 * 60, 9000), entry(9000 + 89 * 60, 20_000)]

    assert Enum.map(TimelineFormat.with_gaps(rows, true), & &1[:minutes]) == [
             nil,
             45,
             nil,
             89,
             nil
           ]

    assert Enum.map(TimelineFormat.with_gaps(rows, false), & &1[:minutes]) == [nil, nil, nil]
  end

  test "with_gaps measures from the furthest covered point, not the previous row" do
    rows = [entry(0, 10_000), entry(1000, 2000), entry(10_000 + 50 * 60, 13_000)]

    assert [%{}, %{}, %{type: "gap", minutes: 50, start_local: local}, %{}] =
             TimelineFormat.with_gaps(rows, true)

    assert local == NaiveDateTime.from_gregorian_seconds(10_000 + 62_167_219_200)
  end

  test "name_parts splits a geocoder string, rejoins house numbers and drops the province" do
    entry = %{
      name: "",
      place: %{name: "Café Kowalski, Karl-Liebknecht-Straße, 10, Leipzig, Sachsen"},
      area: nil
    }

    assert TimelineFormat.name_parts(entry, "en") == %{
             primary: "Café Kowalski",
             secondary: "Karl-Liebknecht-Straße 10, Leipzig"
           }

    assert TimelineFormat.name_parts(%{entry | place: %{name: "Zoo Leipzig"}}, "en") == %{
             primary: "Zoo Leipzig",
             secondary: nil
           }

    assert TimelineFormat.name_parts(%{entry | place: %{name: "Markt, Leipzig"}}, "en") == %{
             primary: "Markt",
             secondary: "Leipzig"
           }
  end

  test "display_name falls back from the visit to its place, its area, then Unnamed" do
    assert TimelineFormat.display_name(
             %{name: "  ", place: nil, area: %{name: "Hauptbahnhof"}},
             "en"
           ) == "Hauptbahnhof"

    assert TimelineFormat.display_name(%{name: nil, place: nil, area: nil}, "en") ==
             DawarichWeb.Translate.t("en", "helpers.timeline.unnamed", %{})
  end

  test "search_tokens joins names, place, area and tags, lowercased" do
    entry = %{
      name: "Morning Coffee",
      editable_name: "Morning Coffee",
      place: %{name: "Café", city: "Leipzig", country: "Germany"},
      area: nil,
      tags: [%{name: "Work"}]
    }

    assert TimelineFormat.search_tokens(entry) ==
             "morning coffee morning coffee café leipzig germany work"
  end

  test "dwell and duration_short use Rails' compact units" do
    t = &DawarichWeb.Translate.t("en", &1, &2)

    assert TimelineFormat.dwell("en", 0) == t.("units.minutes_compact", %{value: 0})
    assert TimelineFormat.dwell("en", 120) == t.("units.hours_compact", %{value: 2})

    assert TimelineFormat.dwell("en", 95) ==
             t.("units.hours_minutes_compact", %{hours: 1, minutes: 35})

    assert TimelineFormat.duration_short("en", nil) == t.("units.minutes_compact", %{value: 0})

    assert TimelineFormat.duration_short("en", 90_000) ==
             t.("units.days_hours_compact", %{days: 1, hours: 1})

    assert TimelineFormat.duration_short("en", 86_400) == t.("units.days_compact", %{value: 1})

    assert TimelineFormat.duration_short("en", 3_720) ==
             t.("units.hours_minutes_compact", %{hours: 1, minutes: 2})

    assert TimelineFormat.duration_short("en", 59) == t.("units.minutes_compact", %{value: 0})
  end

  test "leg_extra grows with the square root of the minutes and stops at 80 px" do
    assert Enum.map([0, 59, 60, 9 * 60, 3600, 1_000_000], &TimelineFormat.leg_extra/1) == [
             0,
             0,
             3,
             10,
             25,
             80
           ]
  end

  test "all_day? by duration or by a midnight start spanning 23 hours" do
    midnight = ~N[2026-09-28 00:00:00]

    assert TimelineFormat.all_day?(%{
             duration: 1380,
             start_local: ~N[2026-09-28 06:00:00],
             start_s: 0,
             end_s: 1
           })

    assert TimelineFormat.all_day?(%{
             duration: 60,
             start_local: midnight,
             start_s: 0,
             end_s: 82_800
           })

    refute TimelineFormat.all_day?(%{
             duration: 60,
             start_local: midnight,
             start_s: 0,
             end_s: 82_799
           })
  end

  test "confidence gating only for unconfirmed visits once re-detected" do
    medium = %{status: "suggested", confidence_band: "medium"}

    assert TimelineFormat.subdued?(medium, true)
    refute TimelineFormat.subdued?(medium, false)
    refute TimelineFormat.subdued?(%{medium | status: "confirmed"}, true)
    assert TimelineFormat.low_confidence?(%{medium | confidence_band: "low"}, true)
  end

  test "cell_classes and mode_icon" do
    cell = %{heat_bucket: 3, suggested_count: 1, in_month: false, disabled: true}

    assert TimelineFormat.cell_classes(cell) ==
             "cal-cell heat-3 has-suggestions out-of-month disabled cal-cell--light-text"

    assert TimelineFormat.cell_classes(%{
             cell
             | heat_bucket: 0,
               suggested_count: 0,
               in_month: true,
               disabled: false
           }) ==
             "cal-cell heat-0 cal-cell--dark-text"

    assert {TimelineFormat.mode_icon("train"), TimelineFormat.mode_icon("hovercraft")} ==
             {"train-front", "route"}
  end

  test "bounds_json is Rails' to_json, empty for no bounds" do
    assert TimelineFormat.bounds_json(nil) == ""

    assert TimelineFormat.bounds_json(%{sw_lat: 51.3, sw_lng: 12.0, ne_lat: 51.35, ne_lng: 12.4}) ==
             ~s({"sw_lat":51.3,"sw_lng":12.0,"ne_lat":51.35,"ne_lng":12.4})
  end

  test "LocalizedDate.l/3 names weekdays from the locale" do
    assert LocalizedDate.l("en", ~D[2026-09-27], "weekday_month_day") == "Sunday, September 27"
    assert LocalizedDate.l("de", ~D[2026-09-27], "weekday_month_day") =~ "Sonntag"
  end
end
