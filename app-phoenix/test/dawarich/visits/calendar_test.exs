defmodule Dawarich.Visits.CalendarTest do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Visits.Calendar

  setup do
    %{f: visits_fixture("calendar_dst")}
  end

  test "Rails' chunk and month bounds", %{f: f} do
    zone = f["calendar"]["time_zone"]

    for range <- f["calendar"]["ranges"] do
      start = local_epoch(range["start_at"], zone)
      stop = local_epoch(range["end_at"], zone)
      assert chunks(zone, start, stop, "calendar") == range["chunks"]
    end

    fixed = f["fixed"]
    assert chunks(zone, fixed["start_at"], fixed["end_at"], "fixed") == fixed["chunks"]

    for [a, b] <- fixed["chunks"], b != fixed["end_at"], do: assert(b - a == 86_400)

    mb = f["month_batches"]

    assert Calendar.month_batches(ScratchRepo, mb["time_zone"], mb["start_at"], mb["end_at"]) ==
             mb["batches"]

    rm = f["redetect_months"]

    assert Calendar.redetect_months(ScratchRepo, rm["time_zone"], rm["min_ts"], rm["max_ts"]) ==
             rm["months"]
  end

  test "a calendar day across the spring change is 23 hours, a fixed step is always 24" do
    zone = "Europe/Berlin"
    noon = local_epoch("2026-03-28T12:00:00", zone)

    assert Calendar.next_day(ScratchRepo, zone, noon, "calendar") - noon == 82_800
    assert Calendar.next_day(ScratchRepo, zone, noon, "fixed") - noon == 86_400
  end

  test "the loop runs while the month cursor is before the end, as Rails' while does" do
    september = 1_788_220_800
    assert Calendar.month_batches(ScratchRepo, "UTC", september, september) == []
    assert Calendar.redetect_months(ScratchRepo, "UTC", september, september) == []

    assert Calendar.month_batches(ScratchRepo, "UTC", 1_790_000_000, 1_790_000_000) ==
             [[1_790_000_000, 1_790_000_000]]
  end

  defp chunks(zone, cursor, stop, stepping) when cursor < stop do
    next = Calendar.next_day(ScratchRepo, zone, cursor, stepping)
    [[cursor, min(next, stop)] | chunks(zone, next, stop, stepping)]
  end

  defp chunks(_zone, _cursor, _stop, _stepping), do: []

  defp local_epoch(iso, zone) do
    [[epoch]] =
      rows("SELECT extract(epoch FROM ($1::timestamp AT TIME ZONE $2))::bigint", [
        NaiveDateTime.from_iso8601!(iso),
        zone
      ])

    epoch
  end
end
