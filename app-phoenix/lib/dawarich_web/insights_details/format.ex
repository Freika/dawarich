defmodule DawarichWeb.InsightsDetails.Format do
  @moduledoc false
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.{Digests, RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def translation(locale, partial, key, bindings \\ %{}),
    do: t(locale, "insights.#{partial}.#{key}", bindings)

  def signed(value), do: if(value > 0, do: "+", else: "") <> Ruby.to_s(value)
  def color(value), do: if(value > 0, do: "success", else: "warning")

  def percentage(value, before) do
    max = max(value, before)
    if max > 0, do: round(value / max * 100), else: 0
  end

  def location_time(locale, minutes) do
    n = Digests.to_i(minutes)

    {key, count} =
      cond do
        n >= 1440 -> {"day_count", div(n, 1440)}
        n >= 60 -> {"hour_count", div(n, 60)}
        true -> {"minute_count", n}
      end

    t(locale, "helpers.insights." <> key, %{count: count})
  end

  def duration(locale, seconds) do
    n = Digests.to_i(seconds)
    days = floor(n / 86400)
    hours = floor((n - days * 86400) / 3600)
    minutes = floor((n - floor(n / 3600) * 3600) / 60)

    cond do
      n == 0 -> t(locale, "units.minutes_compact", %{value: 0})
      days > 0 and hours > 0 -> t(locale, "units.days_hours_compact", %{days: days, hours: hours})
      days > 0 -> t(locale, "units.days_compact", %{value: days})
      hours > 0 -> t(locale, "units.hours_minutes_compact", %{hours: hours, minutes: minutes})
      true -> t(locale, "units.minutes_compact", %{value: minutes})
    end
  end

  def activity_hours(locale, seconds) do
    seconds = Digests.to_i(seconds)
    hours = RubyFloat.round(seconds / 3600.0, 1)

    if hours >= 1 do
      value = if trunc(hours) == hours, do: trunc(hours), else: hours
      t(locale, "units.hours_compact", %{value: Ruby.to_s(value)})
    else
      if seconds == 0,
        do: t(locale, "units.hours_compact", %{value: 0}),
        else: t(locale, "units.minutes_word_compact", %{value: round(seconds / 60.0)})
    end
  end
end
