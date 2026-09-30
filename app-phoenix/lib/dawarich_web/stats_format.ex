defmodule DawarichWeb.StatsFormat do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.Distance
  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{LocalizedDate, NumberFormat, Params}

  @header_colors ~w(info success warning error accent secondary primary)
  @icons [
    {1..2, "snowflake"},
    {3..5, "flower"},
    {6..8, "tree-palm"},
    {9..11, "leaf"},
    {12..12, "snowflake"}
  ]
  @colors ~w(#397bb5 #5A4E9D #3B945E #7BC96F #FFD54F #FFA94D #FF6B6B #FF8C42 #C97E4F #8B4513 #5A2E2E #265d7d)
  @backgrounds ~w(anne-nygard-VwzfdVT6_9s ainars-cekuls-buAAKQiMfoI ahmad-hasan-xEYWelDHYF0 lily-Rg1nSqXNPN4
                  milan-de-clercq-YtllSzi2JLY liana-mikah-6B05zlnPOEc irina-iriser-fKAl8Oid6zM
                  nadiia-ploshchenko-ZnDtJaIec_E gracehues-photography-AYtup7uqimA babi-hdNa4GCCgbg
                  foto-phanatic-8LaUOtP-de4 henry-schneider-FqKPySIaxuE)
  @progress ~w(progress-primary progress-secondary progress-accent progress-info progress-success progress-warning)

  def unit(%{"maps" => %{"distance_unit" => unit}}) when unit not in [nil, false], do: unit
  def unit(_settings), do: "km"

  def convert(nil, _unit), do: 0.0

  def convert(meters, unit) do
    unit = to_string(unit)

    if Distance.unit?(unit),
      do: Distance.convert(meters, unit),
      else: raise(ArgumentError, "Invalid unit '#{unit}'. Supported units: km, mi, m, ft, yd")
  end

  def rounded(meters, unit), do: round(convert(meters, unit))

  def distance(locale, meters, unit),
    do:
      t(locale, "helpers.stats.distance", %{
        value: NumberFormat.delimited(locale, rounded(meters, unit)),
        unit: unit
      })

  def header_color(year), do: Enum.at(@header_colors, rem(year, 7))

  def sample_header_color(user_id, year, now),
    do: header_color_picker(user_id, year, now).(@header_colors)

  defp header_color_picker(user_id, year, now),
    do:
      Application.get_env(
        :dawarich,
        :header_color_picker,
        deterministic_header_color_picker(user_id, year, now)
      )

  defp deterministic_header_color_picker(user_id, year, now) do
    hour = div(DateTime.to_unix(now), 3600)
    fn list -> Enum.at(list, :erlang.phash2({user_id, year, hour}, length(list))) end
  end

  def month_icon(month),
    do: Enum.find_value(@icons, fn {range, icon} -> if month in range, do: icon end)

  def month_color(month), do: Enum.at(@colors, month - 1)

  def month_background(month),
    do: "backgrounds/months/#{Enum.at(@backgrounds, month - 1)}-unsplash.jpg"

  def year_map_path(year),
    do:
      "/map/v2?" <>
        Params.to_query(%{"start_at" => "#{year}-01-01T00:00", "end_at" => "#{year}-12-31T23:59"})

  def active_days(daily), do: "#{active(daily)}/#{length(daily)}"

  def than_average(_locale, _distance, 0), do: ""

  def than_average(locale, distance, average) do
    difference = distance / 1000.0 - average
    direction = if difference > 0, do: "more", else: "less"

    t(locale, "helpers.stats_comparison.distance.#{direction}", %{
      percentage: abs(round(difference / average * 100))
    })
  end

  def than_previous_active_days(_locale, _daily, nil), do: ""

  def than_previous_active_days(locale, daily, previous),
    do: comparison(locale, "active_days", active(daily) - active(previous.daily))

  def than_previous_countries(_locale, _toponyms, nil), do: ""

  def than_previous_countries(locale, toponyms, previous),
    do:
      comparison(
        locale,
        "countries",
        Toponyms.known_countries(toponyms) - Toponyms.known_countries(previous.toponyms)
      )

  def peak(daily) do
    case Enum.max_by(daily, fn [_day, meters] -> meters end, &>=/2, fn -> nil end) do
      [day, meters] when meters > 0 -> {day, meters}
      _ -> nil
    end
  end

  def peak_text(locale, year, month, {day, meters}, unit),
    do:
      t(locale, "helpers.stats.peak_day", %{
        date: LocalizedDate.l(locale, Date.new!(year, month, day), "month_day_padded"),
        distance: t(locale, "helpers.stats.distance", %{value: rounded(meters, unit), unit: unit})
      })

  def peak_href({start, finish}),
    do: "/map/v2?" <> Params.to_query(%{"start_at" => start, "end_at" => finish})

  def quietest_week(locale, _year, _month, []), do: t(locale, "common.not_available", %{})

  def quietest_week(locale, year, month, daily) do
    by_day = Map.new(daily, fn [day, meters] -> {day, meters} end)
    first = Date.new!(year, month, 1)

    {start, _sum} =
      first
      |> Date.range(Date.add(Date.end_of_month(first), -6))
      |> Enum.reduce({nil, :infinity}, fn date, {best, best_sum} ->
        sum = Enum.sum(for offset <- 0..6, do: Map.get(by_day, date.day + offset, 0))
        if sum < best_sum, do: {date, sum}, else: {best, best_sum}
      end)

    t(locale, "helpers.stats.week_range", %{
      start_date: LocalizedDate.l(locale, start, "short_month_day_padded"),
      end_date: LocalizedDate.l(locale, Date.add(start, 6), "short_month_day_padded")
    })
  end

  def city_progress(count, max) when is_integer(max) and max > 0, do: round(count / max * 100)
  def city_progress(_count, _max), do: 0

  def progress_color(index), do: Enum.at(@progress, rem(index, 6))

  def upgrade_url(_user, _now, true, _medium, _content), do: ""

  def upgrade_url(user, now, false, medium, content) do
    utm = %{
      "utm_source" => "app",
      "utm_medium" => medium,
      "utm_campaign" => "lite_upgrade",
      "utm_content" => content
    }

    Dawarich.SubscriptionToken.url(user, now) <> "&" <> Params.to_query(utm)
  end

  defp active(daily), do: Enum.count(daily, fn [_day, meters] -> meters > 0 end)

  defp comparison(locale, _kind, 0),
    do: t(locale, "helpers.stats_comparison.same_as_previous_month", %{})

  defp comparison(locale, kind, difference) do
    direction = if difference > 0, do: "more", else: "less"
    t(locale, "helpers.stats_comparison.#{kind}.#{direction}", %{count: abs(difference)})
  end
end
