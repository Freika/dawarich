defmodule Dawarich.Mail.Digests.Render do
  @moduledoc false
  require EEx

  alias Dawarich.{I18n, RubyFloat}
  alias Dawarich.Mail.{ExploreFeatures, Layout}
  alias Dawarich.Mail.Digests.{Charts, Data}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{LocalizedDate, NumberFormat}

  @dir Path.expand("../../../../priv/mail/digests", __DIR__)
  @pre_style "white-space: pre; font-family: ui-monospace, \"SF Mono\", Menlo, Consolas, monospace; line-height: 1.25; font-size: 13px; background: #fff; padding: 16px; border-radius: 6px; border: 1px solid #e5e5e5; overflow-x: auto; margin: 0 0 1em 0;"

  for period <- ~w(monthly yearly), format <- ~w(html text) do
    file = Path.join(@dir, "#{period}.#{format}.eex")
    @external_resource file
    compiled = EEx.compile_file(file)

    defp body(unquote(period), unquote(format), unquote({:assigns, [], nil})),
      do: unquote(compiled)
  end

  def message(repo, user, digest, ambient, env, base_url) do
    locale = ExploreFeatures.locale(user.settings, ambient)
    period = digest["period_type"]
    projection = Data.project(repo, user, digest)

    scope =
      "users.digests_mailer." <>
        if(period == "monthly", do: "monthly_digest", else: "year_end_digest")

    t = fn key, bindings -> text!(locale, scope <> "." <> key, bindings) end
    assigns = assigns(digest, projection, locale, base_url, t)
    html = Map.merge(assigns, %{t: &ExploreFeatures.h(t.(&1, %{})), v: &ExploreFeatures.h/1})
    text = Map.merge(assigns, %{t: &t.(&1, %{}), v: &string/1})

    subject_key = if period == "monthly", do: "monthly", else: "year_end"

    %{
      from: env["SMTP_FROM"],
      to: user.email,
      locale: locale,
      subject:
        text!(locale, "mailers.users.digests." <> subject_key <> ".subject", assigns.bindings),
      html: Layout.html(locale, body(period, "html", html)),
      text: Layout.text(body(period, "text", text))
    }
  end

  defp assigns(digest, projection, locale, base_url, t) do
    unit = projection["distance_unit"]
    monthly = digest["period_type"] == "monthly"
    bindings = %{"year" => digest["year"]}

    bindings =
      if monthly,
        do:
          Map.put(
            bindings,
            "month",
            LocalizedDate.month_name(locale, digest["year"], digest["month"])
          ),
        else: bindings

    title = if monthly, do: "month_year_in_review", else: "year_in_review_title"

    subtitle =
      if monthly,
        do: "here_s_what_your_location_history_looked_like_last_month",
        else: "year_at_a_glance"

    locations = Data.object(digest["time_spent_by_location"])
    stats = Data.object(digest["all_time_stats"])
    percent = Data.object(digest["year_over_year"])["distance_change_percent"]
    countries = projection["top_countries"]
    cities = projection["top_cities"] || []
    first_countries = Enum.take(projection["first_countries"] || [], 2)
    first_cities = Enum.take(projection["first_cities"] || [], 3 - length(first_countries))

    lines =
      Enum.map(first_countries, &t.("new_country_line", %{"country" => &1})) ++
        Enum.map(first_cities, &t.("new_city_line", %{"city" => &1}))

    %{
      pre_style: @pre_style,
      bindings: bindings,
      title: t.(title, bindings),
      subtitle: t.(subtitle, bindings),
      distance: distance(digest["distance"], unit, locale),
      flight_distance: distance(digest["flight_distance"], unit, locale),
      flights?: Data.number(digest["flight_distance"]) > 0,
      active_days: projection["active_days"],
      countries_count:
        if(monthly,
          do: length(Data.array(locations["countries"])),
          else: stats["total_countries"]
        ),
      cities_count:
        if(monthly, do: length(Data.array(locations["cities"])), else: stats["total_cities"]),
      top_countries?: countries != [],
      top_cities?: cities != [],
      countries_chart: ranked(if(monthly, do: countries, else: Enum.take(countries, 5))),
      cities_chart: ranked(Enum.take(cities, 5)),
      first_visits?:
        (projection["first_countries"] || []) != [] or (projection["first_cities"] || []) != [],
      first_visits: Enum.join(lines, "\n"),
      first_country_lines: Enum.map(first_countries, &t.("new_country_line", %{"country" => &1})),
      first_city_lines: Enum.map(first_cities, &t.("new_city_line", %{"city" => &1})),
      trend?: Ruby.present?(percent),
      trend: Charts.trend_from_pct(digest["distance"], percent, locale: locale),
      insights_url: base_url <> "/insights" <> if(monthly, do: utm("view_insights"), else: ""),
      preferences_url:
        base_url <>
          "/settings/general" <>
          if(monthly, do: utm("manage_preferences"), else: "") <> "#email-digests",
      shared?: Ruby.present?(digest["sharing_uuid"]),
      shared_url: base_url <> "/shared/digest/" <> string(digest["sharing_uuid"])
    }
    |> Map.merge(charts(projection, digest["year"], locale))
  end

  defp charts(%{"daily_distances" => distances} = projection, _year, locale)
       when is_map(distances) do
    {:ok, days} = I18n.t(locale, "date.abbr_day_names")
    [sunday | rest] = days

    values =
      for day <- 1..31,
          distance = Data.number(distances[to_string(day)]),
          distance != 0,
          do: distance

    values = if values == [], do: [0], else: values

    %{
      weekly:
        Charts.hbar(projection["weekday_totals"],
          labels: rest ++ [sunday],
          width: 20,
          suffix: " " <> projection["distance_unit"]
        ),
      daily: Charts.sparkline(values)
    }
  end

  defp charts(projection, year, locale) do
    {:ok, months} = I18n.t(locale, "date.abbr_month_names")

    values =
      for month <- 1..12,
          do: RubyFloat.round(Data.number(projection["monthly_distances"][to_string(month)]))

    daily =
      Map.new(projection["daily_values"], fn {date, value} ->
        {Date.from_iso8601!(date), value}
      end)

    %{
      monthly:
        Charts.hbar(values,
          labels: Enum.reject(months, &is_nil/1),
          width: 24,
          suffix: " " <> projection["distance_unit"]
        ),
      heatmap?: map_size(daily) > 0,
      heatmap: Charts.year_heatmap(daily, start_date: Date.new!(year, 1, 1))
    }
  end

  defp ranked(items),
    do:
      Charts.ranked_list(items,
        value_key: "minutes",
        label_key: "name",
        width: 20,
        format: &"#{RubyFloat.round(Data.number(&1) / 60)}h"
      )

  defp distance(value, unit, locale) do
    converted =
      NumberFormat.delimited(locale, RubyFloat.round(Data.convert_distance(value, unit)))

    text!(locale, "helpers.users.digests.distance_with_unit", %{
      "distance" => converted,
      "unit" => unit
    })
  end

  defp utm(content),
    do:
      "?utm_campaign=monthly_digest&utm_content=" <>
        content <> "&utm_medium=email&utm_source=email"

  defp string(nil), do: ""
  defp string(value), do: Ruby.to_s(value)

  defp text!(locale, key, bindings) do
    {:ok, text} = I18n.t(locale, key, bindings)
    text
  end
end
