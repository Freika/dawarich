defmodule Dawarich.Mail.Digests.Charts do
  @moduledoc false

  alias Dawarich.{I18n, RubyFloat}
  alias Dawarich.Mail.Digests.Data
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @blocks ~w(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

  def hbar(values, opts \\ [])
  def hbar([], _opts), do: ""

  def hbar(values, opts) do
    labels = Keyword.fetch!(opts, :labels)
    width = Keyword.get(opts, :width, 24)
    suffix = Keyword.get(opts, :suffix, "")
    max = values |> Enum.map(&Data.number/1) |> Enum.max() |> nonzero()
    label_width = labels |> Enum.map(&size/1) |> Enum.max(fn -> 0 end)

    values
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {value, index} ->
      label = labels |> Enum.at(index) |> pad(label_width)
      label <> "  " <> bar(value, max, width) <> "  " <> string(value) <> suffix
    end)
  end

  def sparkline(values, opts \\ [])
  def sparkline([], _opts), do: ""

  def sparkline(values, _opts) do
    numbers = Enum.map(values, &Data.number/1)
    max = Enum.max(numbers)
    min = Enum.min(numbers)

    if max == min do
      String.duplicate(List.last(@blocks), length(values))
    else
      Enum.map_join(numbers, fn value ->
        Enum.at(@blocks, RubyFloat.round((value - min) / (max - min) * 7))
      end)
    end
  end

  def year_heatmap(values, opts) do
    start = Keyword.fetch!(opts, :start_date)
    positive = values |> Map.values() |> Enum.filter(&(Data.number(&1) > 0)) |> Enum.sort()
    count = length(positive)

    thresholds =
      if count == 0,
        do: [0, 0, 0],
        else: Enum.map([div(count, 4), div(count, 2), div(count * 3, 4)], &Enum.at(positive, &1))

    grid_start = Date.add(start, 1 - Date.day_of_week(start))
    last = values |> Map.keys() |> Enum.max(Date, fn -> start end)
    weeks = Integer.floor_div(Date.diff(last, grid_start), 7) + 1
    columns = if weeks > 0, do: 0..(weeks - 1), else: []

    Enum.map_join(0..6, "\n", fn weekday ->
      Enum.map_join(columns, fn week ->
        date = Date.add(grid_start, week * 7 + weekday)
        if Date.after?(date, last), do: " ", else: level(Data.number(values[date]), thresholds)
      end)
    end)
  end

  def trend(current, previous, opts \\ []) do
    current = Data.number(current)
    previous = Data.number(previous)

    cond do
      current == previous -> translated(opts, "same")
      previous == 0 -> translated(opts, "new")
      true -> delta(current, previous)
    end
  end

  def trend_from_pct(current, percent, opts \\ []) do
    if is_nil(percent) do
      translated(opts, "same")
    else
      denominator = 1 + Data.number(percent) / 100

      if denominator == 0,
        do: translated(opts, if(Data.number(current) > 0, do: "new", else: "same")),
        else: trend(current, Data.number(current) / denominator, opts)
    end
  end

  def ranked_list(items, opts)
  def ranked_list([], _opts), do: ""

  def ranked_list(items, opts) do
    value_key = Keyword.fetch!(opts, :value_key)
    label_key = Keyword.fetch!(opts, :label_key)
    width = Keyword.get(opts, :width, 20)
    format = Keyword.get(opts, :format, &string/1)
    sorted = Enum.sort_by(items, &(-Data.number(&1[value_key])))
    max = sorted |> hd() |> Map.get(value_key) |> Data.number() |> nonzero()
    label_width = sorted |> Enum.map(&size(&1[label_key])) |> Enum.max()

    sorted
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {item, index} ->
      "#{index}. " <>
        pad(item[label_key], label_width) <>
        "  " <>
        bar(item[value_key], max, width) <> "  " <> string(format.(item[value_key]))
    end)
  end

  defp level(value, _thresholds) when value == 0, do: "·"

  defp level(value, [first, second, third]) do
    cond do
      value < first -> "░"
      value < second -> "▒"
      value < third -> "▓"
      true -> "█"
    end
  end

  defp bar(value, max, width) do
    fill = RubyFloat.round(Data.number(value) / max * width)
    if fill < 0, do: raise(ArgumentError, "negative chart width")
    pad(String.duplicate("█", fill), width)
  end

  defp delta(current, previous) do
    value = RubyFloat.round((current - previous) / previous * 100)
    if value > 0, do: "↑ +#{value}%", else: "↓ #{value}%"
  end

  defp translated(opts, key) do
    {:ok, text} = I18n.t(Keyword.get(opts, :locale, "en"), "helpers.users.digests_mailer." <> key)
    text
  end

  defp nonzero(value), do: if(value == 0, do: 1.0, else: value)
  defp string(nil), do: ""
  defp string(value), do: Ruby.to_s(value)
  defp size(value), do: value |> string() |> String.codepoints() |> length()
  defp pad(value, width), do: string(value) <> String.duplicate(" ", max(width - size(value), 0))
end
