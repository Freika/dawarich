defmodule DawarichWeb.HumanDatetime do
  @moduledoc false
  use Phoenix.Component

  attr :locale, :string, required: true
  attr :at, :map, required: true

  def human_datetime(assigns) do
    ~H|<span class="tooltip" data-tip={iso8601(@at)}>{text(@locale, @at.local)}</span>|
  end

  attr :locale, :string, required: true
  attr :at, :map, required: true

  def human_datetime_with_seconds(assigns) do
    ~H|<span class="tooltip" data-tip={iso8601(@at)}>{text(@locale, @at.local, "human_with_seconds")}</span>|
  end

  def text(locale, local, format \\ "human") do
    {:ok, pattern} = Dawarich.I18n.t(locale, "time.formats." <> format)
    {:ok, months} = Dawarich.I18n.t(locale, "date.abbr_month_names")

    Calendar.strftime(local, String.replace(pattern, "%e", "%_d"),
      abbreviated_month_names: &Enum.at(months, &1)
    )
  end

  def iso8601(%{local: local, utc: true}), do: stamp(local) <> "Z"

  def iso8601(%{local: local, offset: offset}) do
    minutes = div(abs(offset), 60)
    sign = if offset < 0, do: "-", else: "+"
    stamp(local) <> sign <> pad(div(minutes, 60)) <> ":" <> pad(rem(minutes, 60))
  end

  defp stamp(local), do: Calendar.strftime(local, "%Y-%m-%dT%H:%M:%S")
  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
