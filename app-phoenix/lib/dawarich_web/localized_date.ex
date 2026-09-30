defmodule DawarichWeb.LocalizedDate do
  @moduledoc false

  def l(locale, %Date{} = date, format) do
    {:ok, pattern} = Dawarich.I18n.t(locale, "date.formats." <> format)
    months = names(locale, "date.month_names")
    abbreviated = names(locale, "date.abbr_month_names")

    Calendar.strftime(date, String.replace(pattern, "%e", "%_d"),
      month_names: &Enum.at(months, &1),
      abbreviated_month_names: &Enum.at(abbreviated, &1)
    )
  end

  def month_name(locale, year, month), do: l(locale, Date.new!(year, month, 1), "month_name")

  def abbr_month(locale, index), do: Enum.at(names(locale, "date.abbr_month_names"), index)

  def time(locale, %NaiveDateTime{} = local, format) do
    {:ok, pattern} = Dawarich.I18n.t(locale, "time.formats." <> format)
    months = names(locale, "date.month_names")
    abbreviated = names(locale, "date.abbr_month_names")
    days = names(locale, "date.day_names")
    abbreviated_days = names(locale, "date.abbr_day_names")

    Calendar.strftime(local, String.replace(pattern, "%e", "%_d"),
      month_names: &Enum.at(months, &1),
      abbreviated_month_names: &Enum.at(abbreviated, &1),
      day_of_week_names: &Enum.at(days, rem(&1, 7)),
      abbreviated_day_of_week_names: &Enum.at(abbreviated_days, rem(&1, 7))
    )
  end

  defp names(locale, key) do
    {:ok, names} = Dawarich.I18n.t(locale, key)
    names
  end
end
