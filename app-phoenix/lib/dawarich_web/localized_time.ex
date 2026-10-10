defmodule DawarichWeb.LocalizedTime do
  @moduledoc false

  def l(locale, %NaiveDateTime{} = time, format) do
    {:ok, pattern} = Dawarich.I18n.t(locale, "time.formats." <> format)

    [days, short_days, months, short_months] =
      Enum.map(~w(day_names abbr_day_names month_names abbr_month_names), &names(locale, &1))

    Calendar.strftime(time, String.replace(pattern, "%e", "%_d"),
      month_names: &Enum.at(months, &1),
      abbreviated_month_names: &Enum.at(short_months, &1),
      day_of_week_names: &Enum.at(days, rem(&1, 7)),
      abbreviated_day_of_week_names: &Enum.at(short_days, rem(&1, 7))
    )
  end

  defp names(locale, key) do
    {:ok, names} = Dawarich.I18n.t(locale, "date." <> key)
    names
  end
end
