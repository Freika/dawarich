defmodule DawarichWeb.InsightsDetails.MonthFormat do
  @moduledoc false
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Digests
  alias Dawarich.Insights.Details.CountryCodes
  alias Dawarich.Insights.Details.Digests, as: DetailDigests
  alias DawarichWeb.{LocalizedDate, NumberFormat, StatsFormat}
  def month(locale, digest), do: LocalizedDate.month_name(locale, digest["year"], digest["month"])

  def title(locale, digest),
    do:
      t(locale, "helpers.insights.monthly_digest_title", %{
        month: month(locale, digest),
        year: digest["year"]
      })

  def distance(locale, digest, unit),
    do:
      t(locale, if(unit == "mi", do: "units.miles", else: "units.kilometers"), %{
        value: NumberFormat.delimited(locale, StatsFormat.rounded(digest["distance"], unit))
      })

  def path(year, month), do: "/insights/details?month=#{month}&year=#{year}"

  def adjacent(year, month, available, direction) do
    date = Date.new!(year, month, 1)
    next = if direction == -1, do: Date.add(date, -1), else: Date.add(Date.end_of_month(date), 1)
    if next.year == year and next.month in available, do: path(next.year, next.month)
  end

  def active_days(digest) do
    daily = digest["monthly_distances"]

    pairs =
      if is_map(daily),
        do: Map.to_list(daily),
        else: Enum.map(daily || [], fn [day, n] -> {day, n} end)

    active = Enum.count(pairs, fn {_day, n} -> Digests.to_i(n) > 0 end)
    "#{active}/#{Date.days_in_month(Date.new!(digest["year"], digest["month"], 1))}"
  end

  def chart(locale, digest, unit) do
    {:ok, names} = Dawarich.I18n.t(locale, "calendar.abbreviated_weekdays")

    weekly =
      DetailDigests.weekly_pattern(digest["year"], digest["month"], digest["monthly_distances"])

    for {name, n} <- Enum.zip(names, weekly), do: [name, StatsFormat.rounded(n, unit)]
  end

  def top_locations(data) do
    entries =
      for %{} = toponym <- data.monthly["toponyms"] || [],
          is_list(toponym["cities"]),
          %{} = city <- toponym["cities"] do
        codes = Map.get_lazy(data, :country_codes, &CountryCodes.load/0)

        %{
          name: "#{city["city"]}, #{country_code(toponym["country"], codes)}",
          minutes: Digests.to_i(city["stayed_for"])
        }
      end

    entries |> Enum.sort_by(&(-&1.minutes)) |> Enum.take(3)
  end

  defp country_code(country, codes) do
    case CountryCodes.lookup(country, codes) do
      value when value not in [nil, false] -> value
      _ -> if country, do: country |> String.slice(0, 2) |> String.upcase(), else: "??"
    end
  end
end
