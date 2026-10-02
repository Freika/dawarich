defmodule Dawarich.Insights.Fragments do
  @moduledoc "The six actual Rails insight fragment keys, SafeBuffers and24hour cache policy."
  alias Dawarich.{RailsCache, UserTimeZone}
  alias Dawarich.RailsCache.Snapshot
  alias DawarichWeb.InsightsDetails
  @template "views/insights/details:9efea8724129ec15ede1d72979639af7"
  @parts [
    {"year_comparison", InsightsDetails.YearComparison},
    {"activity_breakdown", InsightsDetails.Activity},
    {"location_clusters", InsightsDetails.Locations},
    {"monthly_digest", InsightsDetails.Monthly},
    {"travel_patterns", InsightsDetails.Travel},
    {"movement_wellness", InsightsDetails.Wellness}
  ]

  def render(user, locale, data, opts) do
    for {name, module} <- @parts, into: %{} do
      cache_key = key(user, locale, data, name)

      value =
        case RailsCache.get(cache_key) do
          {:ok, value} ->
            Snapshot.html(value)

          _ ->
            html =
              module.render(%{__changed__: nil, locale: locale, data: data})
              |> Phoenix.HTML.Safe.to_iodata()
              |> IO.iodata_to_binary()

            if opts[:write], do: RailsCache.put(cache_key, html, expires_in: 86400)

            html
        end

      {name, value}
    end
  end

  def key(user, locale, data, name) do
    common = [
      @template,
      user.id,
      "insights",
      locale,
      data.selected,
      timestamp(user, data.max_stat_updated),
      data.unit,
      name
    ]

    pieces = if name == "monthly_digest", do: common ++ [data.selected_month], else: common
    Enum.map_join(pieces, "/", &to_string/1)
  end

  defp timestamp(_user, nil), do: ""

  defp timestamp(user, time) do
    [[local, seconds]] =
      UserTimeZone.query!(
        "SELECT $1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE z.name,EXTRACT(epoch FROM (($1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE z.name)-$1::timestamp))::integer FROM z",
        [time],
        user.settings
      ).rows

    offset = abs(seconds) |> div(60)
    sign = if seconds < 0, do: "-", else: "+"
    suffix = sign <> pad(div(offset, 60)) <> pad(rem(offset, 60))
    Calendar.strftime(local, "%Y-%m-%d %H:%M:%S") <> " " <> suffix
  end

  defp pad(n), do: n |> to_string() |> String.pad_leading(2, "0")
end
