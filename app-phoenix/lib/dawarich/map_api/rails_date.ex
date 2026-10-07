defmodule Dawarich.MapApi.RailsDate do
  @moduledoc false
  alias Dawarich.Imports.DateParts

  def parse(value) when is_binary(value) do
    fields = DateParts.parse(value)
    today = Date.utc_today()
    year = year(fields["year"] || fields["cwyear"] || today.year, value, fields)

    cond do
      Map.has_key?(fields, "yday") ->
        date = Date.new!(year, 1, 1) |> Date.add(fields["yday"] - 1)
        if fields["yday"] >= 1 and date.year == year, do: {:ok, date}, else: :error

      Map.has_key?(fields, "cweek") or Map.has_key?(fields, "cwday") ->
        {current_year, current_week} =
          :calendar.iso_week_number({today.year, today.month, today.day})

        year = if fields["cwyear"], do: year, else: current_year
        week = Map.get(fields, "cweek", if(fields["cwyear"], do: 1, else: current_week))
        day = Map.get(fields, "cwday", 1)
        jan4 = Date.new!(year, 1, 4)
        date = Date.add(jan4, 1 - Date.day_of_week(jan4) + (week - 1) * 7 + day - 1)
        {iso_year, iso_week} = :calendar.iso_week_number({date.year, date.month, date.day})
        if iso_year == year and iso_week == week and day in 1..7, do: {:ok, date}, else: :error

      Map.has_key?(fields, "year") or Map.has_key?(fields, "mon") or Map.has_key?(fields, "mday") ->
        Date.new(
          year,
          Map.get(fields, "mon", if(fields["year"], do: 1, else: today.month)),
          Map.get(fields, "mday", 1)
        )

      Map.has_key?(fields, "wday") ->
        {:ok, Date.add(today, fields["wday"] - rem(Date.day_of_week(today), 7))}

      true ->
        :error
    end
  rescue
    _ -> :error
  end

  def parse(_), do: :error

  defp year(n, text, fields) when n in 0..99 do
    explicit =
      not Map.has_key?(fields, "yday") and not Map.has_key?(fields, "cwyear") and
        Regex.match?(~r/(?:\b\d{4}[-\/.]|[-\/.]\d{4}\b|\b\d{4}\b|\b\d{8}\b)/, text)

    if explicit, do: n, else: if(n < 69, do: 2000 + n, else: 1900 + n)
  end

  defp year(n, _text, _fields), do: n
end
