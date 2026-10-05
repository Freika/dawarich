defmodule Dawarich.MapWindowTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.MapWindow
  alias DawarichWeb.LocalizedDate

  @now ~U[2026-09-29 10:00:00Z]
  @berlin %{"timezone" => "Europe/Berlin"}

  defp build(params, settings \\ @berlin, range \\ nil, env \\ %{}),
    do: MapWindow.build(params, settings, @now, range, env)

  test "today in the user's zone when nothing is asked" do
    w = build(%{})
    assert {w.start, w.end} == {"2026-09-29T00:00:00+02:00", "2026-09-29T23:59:59+02:00"}
    assert {w.start_local, w.end_local} == {"2026-09-29T00:00", "2026-09-29T23:59"}
    assert w.prev == {"2026-09-28T00:00:00+02:00", "2026-09-28T23:59:59+02:00"}
    assert w.next == {"2026-09-30T00:00:00+02:00", "2026-09-30T23:59:59+02:00"}
    assert w.today == {"2026-09-29T00:00:00+02:00", "2026-09-29T23:59:59+02:00"}

    assert {w.week_start, w.month_start} ==
             {"2026-09-22T00:00:00+02:00", "2026-08-29T00:00:00+02:00"}

    assert {w.zone, w.iana, w.calendar_month} == {"Europe/Berlin", "Europe/Berlin", "2026-09"}
  end

  test "explicit local times are the user's wall clock; an offset or digits are absolute" do
    w = build(%{"start_at" => "2025-10-15T00:00", "end_at" => "2025-10-15T23:59"})
    assert {w.start, w.end} == {"2025-10-15T00:00:00+02:00", "2025-10-15T23:59:00+02:00"}
    assert LocalizedDate.l("en", w.prev_date, "day_month_year") == "14 October 2025"

    w = build(%{"start_at" => "2025-10-15T00:00:00+05:00", "end_at" => "1760486400"})
    assert {w.start, w.end} == {"2025-10-14T21:00:00+02:00", "2025-10-15T02:00:00+02:00"}
  end

  test "digits are clamped to 1970–2100 in the user's zone, garbage means now" do
    w = build(%{"start_at" => "99999999999", "end_at" => "0"})
    assert {w.start, w.end} == {"2100-01-01T00:00:00+01:00", "1970-01-01T01:00:00+01:00"}

    w = build(%{"start_at" => "garbage", "end_at" => "2025-13-45T10:00"})
    assert {w.start, w.end} == {"2026-09-29T12:00:00+02:00", "2026-09-29T12:00:00+02:00"}
  end

  test "?date= uses the settings zone, or UTC when the setting is blank" do
    w = build(%{"date" => "2026-05-28", "panel" => "timeline"})
    assert {w.start, w.end} == {"2026-05-28T00:00:00+02:00", "2026-05-28T23:59:59+02:00"}
    assert w.calendar_month == "2026-05"

    w = build(%{"date" => "2026-05-28"}, %{"timezone" => ""})
    assert {w.zone, w.iana} == {"Europe/Berlin", "Europe/Berlin"}
    assert {w.start, w.end} == {"2026-05-28T02:00:00+02:00", "2026-05-29T01:59:59+02:00"}

    w = build(%{"date" => "2026-05-28", "start_at" => "2026-05-20T08:00"})
    assert {w.start, w.end} == {"2026-05-20T08:00:00+02:00", "2026-05-28T23:59:59+02:00"}
  end

  test "a local time in the autumn overlap is the earlier instant; one in the spring gap moves forward" do
    w = build(%{"start_at" => "2026-03-29T02:30", "end_at" => "2026-10-25T02:30"})
    assert {w.start, w.end} == {"2026-03-29T03:30:00+02:00", "2026-10-25T02:30:00+02:00"}
  end

  test "non-hour overlap and gap follow Rails local-time resolution" do
    w =
      build(
        %{"start_at" => "2026-04-05T01:45", "end_at" => "2026-10-04T02:15"},
        %{"timezone" => "Australia/Lord_Howe"}
      )

    assert {w.start, w.end} ==
             {"2026-04-05T01:45:00+11:00", "2026-10-04T03:15:00+11:00"}
  end

  test "two-hour overlap selects the Rails daylight period" do
    w =
      build(
        %{"start_at" => "2026-10-25T01:30", "end_at" => "2026-10-25T01:45"},
        %{"timezone" => "Antarctica/Troll"}
      )

    assert {w.start, w.end} ==
             {"2026-10-25T01:30:00+02:00", "2026-10-25T01:45:00+02:00"}
  end

  test "an overlap between two periods with the same daylight flag resolves to the later instant" do
    w =
      build(
        %{"start_at" => "2018-03-11T02:30", "end_at" => "2023-03-09T01:30"},
        %{"timezone" => "Antarctica/Casey"}
      )

    assert {w.start, w.end} == {"2018-03-11T02:30:00+08:00", "2023-03-09T01:30:00+08:00"}

    w =
      build(
        %{"start_at" => "2023-12-18T00:30", "end_at" => "2023-12-18T01:45"},
        %{"timezone" => "Antarctica/Vostok"}
      )

    assert {w.start, w.end} == {"2023-12-18T00:30:00+05:00", "2023-12-18T01:45:00+05:00"}
  end

  test "a zone with both kinds of overlap takes the later instant, then the daylight one" do
    w =
      build(
        %{"start_at" => "2015-10-04T01:45", "end_at" => "2026-04-05T02:30"},
        %{"timezone" => "Pacific/Norfolk"}
      )

    assert {w.start, w.end} == {"2015-10-04T01:45:00+11:00", "2026-04-05T02:30:00+12:00"}
  end

  test "Rails zone names map to IANA and UTC zones print Z" do
    assert build(%{}, %{"timezone" => "Berlin"}).iana == "Europe/Berlin"
    assert build(%{}, %{"timezone" => "Eastern Time (US & Canada)"}).iana == "America/New_York"
    w = build(%{"date" => "2026-05-28"}, %{})
    assert {w.zone, w.iana, w.start} == {"Etc/UTC", "Etc/UTC", "2026-05-28T00:00:00Z"}
    assert build(%{}, %{"timezone" => "Not/AZone"}).iana == "Etc/UTC"
  end

  test "the import's first and last point days frame the window" do
    w = build(%{}, %{"timezone" => "Asia/Kolkata"}, {1_767_225_600, 1_767_400_000})
    assert {w.start, w.end} == {"2026-01-01T00:00:00+05:30", "2026-01-03T23:59:59+05:30"}

    w =
      build(
        %{"date" => "2026-01-02"},
        %{"timezone" => "Asia/Kolkata"},
        {1_767_225_600, 1_767_400_000}
      )

    assert w.start == "2026-01-02T00:00:00+05:30"
  end

  test "every corpus case matches what Rails rendered" do
    corpus = "test/fixtures/map_window.json" |> File.read!() |> Jason.decode!()
    {:ok, now, 0} = DateTime.from_iso8601(corpus["now"])
    env = Map.reject(corpus["env"], fn {_key, value} -> is_nil(value) end)

    for c <- corpus["cases"] do
      settings = if is_nil(c["tz"]), do: %{}, else: %{"timezone" => c["tz"]}
      range = c["import"] && {c["import"]["min"], c["import"]["max"]}
      w = MapWindow.build(c["params"], settings, now, range, env)
      x = c["expected"]
      label = inspect({c["tz"], c["params"]})

      assert {w.start, w.end, w.iana} == {x["start"], x["end"], x["iana"]}, label
      assert {w.start_local, w.end_local} == {x["start_local"], x["end_local"]}, label
      assert LocalizedDate.l("en", w.start_date, "day_month_year") == x["label"], label
      assert LocalizedDate.l("en", w.prev_date, "day_month_year") == x["prev_tip"], label
      assert LocalizedDate.l("en", w.next_date, "day_month_year") == x["next_tip"], label

      assert [Tuple.to_list(w.prev), Tuple.to_list(w.next), Tuple.to_list(w.today)] == [
               x["prev"],
               x["next"],
               x["today"]
             ],
             label

      assert [w.week_start, w.month_start] == [hd(x["week"]), hd(x["month"])], label
      assert [Date.to_iso8601(w.start_date), Date.to_iso8601(w.end_date)] == x["share"], label

      if calendar_comparable?(c["params"]), do: assert(w.calendar_month == x["calendar"], label)
    end
  end

  defp calendar_comparable?(params) do
    source = params["date"] || params["start_at"]
    is_nil(source) or source == "today" or Regex.match?(~r/\A\d{4}-/, source)
  end
end
