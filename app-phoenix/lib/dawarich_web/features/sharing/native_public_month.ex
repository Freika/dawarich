defmodule DawarichWeb.NativePublicMonth do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Assets, PublicMonth, StatsFormat}

  def document(assigns), do: DawarichWeb.PublicReportDocument.document(assigns)

  def content(assigns) do
    page = assigns.page
    stat = page.stat
    peak = StatsFormat.peak(stat.daily)
    viewer = assigns.chrome.current_user

    zone =
      Dawarich.UserTimeZone.name(
        if viewer, do: Dawarich.UserSettings.get(viewer), else: %{"timezone" => ""}
      )

    PublicMonth.document(
      Map.merge(assigns, %{
        native: true,
        year: stat.year,
        month: stat.month,
        stat: stat,
        totals: page.totals,
        unit: page.unit,
        peak: peak,
        peak_bounds:
          peak &&
            Dawarich.LocalTime.day_bounds(zone, Date.new!(stat.year, stat.month, elem(peak, 0))),
        bg_url:
          assigns.base_url <> Assets.stylesheet_path(StatsFormat.month_background(stat.month)),
        map_config: %{
          "kind" => "stats",
          "uuid" => assigns.uuid,
          "interactive" => true,
          "bounds" => Map.new(page.bounds || %{}, fn {key, value} -> {to_string(key), value} end),
          "range" => %{"timezone" => page.timezone}
        }
      })
    )
  end
end
