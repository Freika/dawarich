defmodule Dawarich.Imports.ZoneRules do
  @moduledoc false
  @zone ~r/\A(?:[A-Za-z]+|<[^>]+>)([+-]?\d+(?::\d+(?::\d+)?)?)(?:([A-Za-z]+|<[^>]+>)([+-]?\d+(?::\d+(?::\d+)?)?)?)?\z/

  def parse(""), do: nil

  def parse(text) do
    case String.split(text, ",") do
      [names, start, finish] ->
        [_, standard, _dst | rest] = Regex.run(@zone, names)
        dst = List.first(rest)
        standard = -clock(standard)
        daylight = if dst in [nil, ""], do: standard + 3600, else: -clock(dst)
        %{standard: standard, daylight: daylight, start: rule(start), finish: rule(finish)}

      [_names] ->
        nil
    end
  end

  def offset(epoch, year, rules) do
    first = transition(year, rules.start, rules.standard, rules.standard)
    last = transition(year, rules.finish, rules.daylight, rules.standard)

    daylight =
      if first < last, do: epoch >= first && epoch < last, else: epoch >= first || epoch < last

    {if(daylight, do: rules.daylight, else: rules.standard), daylight}
  end

  def transitions(year, rules) do
    [
      {transition(year, rules.start, rules.standard, rules.standard), {rules.daylight, true}},
      {transition(year, rules.finish, rules.daylight, rules.standard), {rules.standard, false}}
    ]
    |> Enum.sort()
  end

  defp rule(text) do
    {date, time} =
      case String.split(text, "/", parts: 2) do
        [date] -> {date, "2"}
        [date, time] -> {date, time}
      end

    kind =
      case date do
        "M" <> fields -> {:month, fields |> String.split(".") |> Enum.map(&String.to_integer/1)}
        "J" <> n -> {:julian, String.to_integer(n)}
        n -> {:day, String.to_integer(n)}
      end

    suffix = if time =~ ~r/[uswgz]\z/, do: String.last(time), else: "w"
    %{date: kind, seconds: clock(String.trim_trailing(time, suffix)), suffix: suffix}
  end

  defp transition(year, rule, previous, standard) do
    date = date(year, rule.date)

    utc_offset =
      case rule.suffix do
        "s" -> standard
        suffix when suffix in ["u", "g", "z"] -> 0
        _ -> previous
      end

    date
    |> NaiveDateTime.new!(~T[00:00:00])
    |> NaiveDateTime.add(rule.seconds - utc_offset)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  defp date(year, {:month, [month, week, weekday]}) do
    first = Date.new!(year, month, 1)
    day = 1 + Integer.mod(weekday - rem(Date.day_of_week(first), 7), 7) + (week - 1) * 7
    day = if day > Date.days_in_month(first), do: day - 7, else: day
    Date.add(first, day - 1)
  end

  defp date(year, {:julian, n}),
    do:
      Date.add(
        Date.new!(year, 1, 1),
        n - 1 + if(Date.leap_year?(Date.new!(year, 1, 1)) && n >= 60, do: 1, else: 0)
      )

  defp date(year, {:day, n}), do: Date.add(Date.new!(year, 1, 1), n)

  defp clock(text) do
    sign = if String.starts_with?(text, "-"), do: -1, else: 1

    fields =
      text
      |> String.trim_leading("-")
      |> String.trim_leading("+")
      |> String.split(":")
      |> Enum.map(&String.to_integer/1)

    fields = fields ++ List.duplicate(0, 3 - length(fields))
    [h, m, s] = fields
    sign * (h * 3600 + m * 60 + s)
  end
end
