defmodule DawarichWeb.TimeAgo do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  @year 525_600
  @quarter 131_400
  @three_quarters 394_200

  def words(locale, from, now) do
    {from, to} = ordered(naive(from), naive(now))
    minutes = round(NaiveDateTime.diff(to, from, :microsecond) / 60_000_000)
    {key, count} = bucket(minutes, from, to)

    scope =
      if locale == "de",
        do: "datetime.distance_in_words.dative",
        else: "datetime.distance_in_words"

    t(locale, scope <> "." <> key, %{count: count})
  end

  defp naive(%DateTime{} = time), do: DateTime.to_naive(time)
  defp naive(%NaiveDateTime{} = time), do: time

  defp ordered(a, b), do: if(NaiveDateTime.compare(a, b) == :gt, do: {b, a}, else: {a, b})

  defp bucket(0, _from, _to), do: {"less_than_x_minutes", 1}
  defp bucket(minutes, _from, _to) when minutes < 45, do: {"x_minutes", minutes}
  defp bucket(minutes, _from, _to) when minutes < 90, do: {"about_x_hours", 1}
  defp bucket(minutes, _from, _to) when minutes < 1440, do: {"about_x_hours", round(minutes / 60)}
  defp bucket(minutes, _from, _to) when minutes < 2520, do: {"x_days", 1}
  defp bucket(minutes, _from, _to) when minutes < 43_200, do: {"x_days", round(minutes / 1440)}

  defp bucket(minutes, _from, _to) when minutes < 86_400,
    do: {"about_x_months", round(minutes / 43_200)}

  defp bucket(minutes, _from, _to) when minutes < @year, do: {"x_months", round(minutes / 43_200)}

  defp bucket(minutes, from, to) do
    from_year = if from.month >= 3, do: from.year + 1, else: from.year
    to_year = if to.month < 3, do: to.year - 1, else: to.year
    leap_years = if from_year > to_year, do: 0, else: leaps(to_year) - leaps(from_year - 1)
    offset = minutes - leap_years * 1440
    remainder = Integer.mod(offset, @year)
    years = Integer.floor_div(offset, @year)

    cond do
      remainder < @quarter -> {"about_x_years", years}
      remainder < @three_quarters -> {"over_x_years", years}
      true -> {"almost_x_years", years + 1}
    end
  end

  defp leaps(year), do: div(year, 4) - div(year, 100) + div(year, 400)
end
