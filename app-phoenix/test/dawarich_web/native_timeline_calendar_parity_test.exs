defmodule DawarichWeb.NativeTimelineCalendarParityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.{NativeTimelineCalendar, TimelineCalendar}

  defp cell(date, in_month, bucket, suggested) do
    %{
      date: date,
      in_month: in_month,
      disabled: false,
      heat_bucket: bucket,
      suggested_count: suggested,
      tracked_seconds: bucket * 3600
    }
  end

  defp summary do
    start = ~D[2026-02-23]

    cells =
      for offset <- 0..41 do
        day = Date.add(start, offset)
        cell(Date.to_iso8601(day), day.month == 3, rem(offset, 6), rem(offset, 5))
      end

    %{month: "2026-03", weeks: Enum.chunk_every(cells, 7)}
  end

  defp native(calendar, selected \\ nil) do
    render_component(&NativeTimelineCalendar.calendar/1,
      calendar: calendar,
      locale: "en",
      selected_date: selected
    )
  end

  defp normalized(html) do
    html
    |> String.replace(~r/ href="[^"]*"/, "")
    |> String.replace(~r/ (aria-busy|aria-current|data-month)="[^"]*"/, "")
    |> ParityHTML.normalize()
  end

  test "a loaded month renders the Rails calendar frame markup" do
    rails = render_component(&TimelineCalendar.calendar/1, summary: summary(), locale: "en")

    assert normalized(native(%{status: :ok, summary: summary()})) == normalized(rails)
  end

  test "a loading month paints the Rails skeleton of disabled neutral cells" do
    html = native(%{status: :loading, month: "2026-03", summary: nil}, "2026-03-04")
    tree = LazyHTML.from_fragment(html)
    cells = LazyHTML.query(tree, ".timeline-calendar--loading button.cal-cell[disabled]")

    assert Enum.count(cells) == 42

    assert tree |> LazyHTML.query("button[data-day='2026-02-23']") |> LazyHTML.attribute("class") ==
             ["cal-cell heat-0 cal-cell--dark-text out-of-month"]

    assert tree |> LazyHTML.query("button[data-day='2026-03-04']") |> LazyHTML.attribute("class") ==
             ["cal-cell heat-0 cal-cell--dark-text cal-cell--selected"]

    assert tree |> LazyHTML.query("[data-testid=calendar-title]") |> LazyHTML.text() =~
             "March 2026"
  end
end
