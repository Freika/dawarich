defmodule Dawarich.Insights.Fragments do
  @moduledoc "The six actual Rails insight fragment keys, SafeBuffers and24hour cache policy."
  alias Dawarich.{RailsCache, Repo}
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

  def render(user, locale, data, opts \\ []) do
    for {name, module} <- @parts, into: %{} do
      cache_key = key(user, locale, data, name, opts)

      value =
        case RailsCache.get(cache_key, opts[:cache] || []) do
          {:ok, value} ->
            Snapshot.html(value)

          _ ->
            html =
              module.render(%{
                __changed__: nil,
                locale: locale,
                data: Map.put(data, :cache_options, opts)
              })
              |> Phoenix.HTML.Safe.to_iodata()
              |> IO.iodata_to_binary()

            unless opts[:read_only],
              do:
                RailsCache.put(
                  cache_key,
                  html,
                  (opts[:cache] || []) ++ [expires_in: 86400]
                )

            html
        end

      {name, value}
    end
  end

  def key(user, locale, data, name, opts \\ []) do
    common = [
      @template,
      user.id,
      "insights",
      locale,
      data.selected,
      timestamp(user, data.max_stat_updated, opts),
      data.unit,
      name
    ]

    pieces = if name == "monthly_digest", do: common ++ [data.selected_month], else: common
    Enum.map_join(pieces, "/", &to_string/1)
  end

  defp timestamp(_user, nil, _opts), do: ""

  defp timestamp(user, time, opts) do
    repo = opts[:repo] || Repo
    zone = Dawarich.UserTimeZone.name(user.settings, repo)

    [[local, seconds]] =
      repo.query!(
        "SELECT $1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE $2,EXTRACT(epoch FROM (($1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE $2)-$1::timestamp))::integer",
        [time, zone]
      ).rows

    offset = abs(seconds) |> div(60)
    sign = if seconds < 0, do: "-", else: "+"
    suffix = sign <> pad(div(offset, 60)) <> pad(rem(offset, 60))
    Calendar.strftime(local, "%Y-%m-%d %H:%M:%S") <> " " <> suffix
  end

  defp pad(n), do: n |> to_string() |> String.pad_leading(2, "0")
end
