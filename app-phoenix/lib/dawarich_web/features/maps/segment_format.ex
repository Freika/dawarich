defmodule DawarichWeb.SegmentFormat do
  @moduledoc false
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.{RubyFloat, Tracks.Settings}
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat, as: FloatText

  def modes_for_mode(mode, user, locale) do
    enabled = Settings.enabled_modes(user)
    options = Enum.map(enabled, &{t(locale, "transportation_modes.#{&1}", %{}), &1})

    if mode in enabled,
      do: options,
      else: [
        {t(locale, "helpers.tracks.segments.mode_disabled", %{
           mode: t(locale, "transportation_modes.#{mode}", %{})
         }), mode}
        | options
      ]
  end

  def segment_distance(nil, _unit, _locale), do: "-"

  def segment_distance(meters, unit, locale) do
    km = meters / 1000.0
    value = if unit == "mi", do: km * 0.621371, else: km

    t(locale, "units.#{if unit == "mi", do: "miles", else: "kilometers"}", %{
      value: value |> RubyFloat.round(2) |> FloatText.to_s()
    })
  end

  def segment_duration(nil, _locale), do: "-"

  def segment_duration(duration, locale) do
    minutes = Integer.floor_div(duration, 60)

    if minutes < 60,
      do: t(locale, "units.minutes", %{value: minutes}),
      else:
        t(locale, "units.hours_minutes_compact", %{
          hours: Integer.floor_div(minutes, 60),
          minutes: Integer.mod(minutes, 60)
        })
  end

  def confidence(nil), do: nil
  def confidence(score), do: RubyFloat.round(score * 100.0)
end
