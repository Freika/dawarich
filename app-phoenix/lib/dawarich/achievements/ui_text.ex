defmodule Dawarich.Achievements.UiText do
  @moduledoc false
  alias Dawarich.UserTimeZone

  def t(locale, key, bindings \\ %{}) do
    {:ok, text} = Dawarich.I18n.t(locale, "achievements." <> key, bindings)
    text
  end

  def local_dates(values, settings) do
    {instants, others} =
      values
      |> Enum.uniq()
      |> Enum.map(&{&1, DateTime.from_iso8601(&1)})
      |> Enum.split_with(&match?({_, {:ok, _, _}}, &1))

    zoned =
      if instants == [],
        do: [],
        else:
          UserTimeZone.query!(
            "SELECT (i AT TIME ZONE z.name)::date FROM z, unnest($1::timestamptz[]) WITH ORDINALITY AS u(i, n) ORDER BY n",
            [Enum.map(instants, fn {_, {:ok, instant, _}} -> instant end)],
            settings
          ).rows

    Enum.zip_with(instants, zoned, fn {value, _}, [date] -> {value, date} end)
    |> Map.new()
    |> Map.merge(Map.new(others, fn {value, _} -> {value, iso_date(value)} end))
  end

  defp iso_date(value), do: value |> String.slice(0, 10) |> Date.from_iso8601!()

  def date(locale, date) do
    pattern = t(locale, "cards.date_format") |> String.replace("%e", "%_d")
    {:ok, months} = Dawarich.I18n.t(locale, "date.month_names")
    {:ok, abbr} = Dawarich.I18n.t(locale, "date.abbr_month_names")

    Calendar.strftime(date, pattern,
      month_names: &Enum.at(months, &1),
      abbreviated_month_names: &Enum.at(abbr, &1)
    )
  end

  def timestamp(settings, instant) do
    %{local: local, offset: offset, utc: utc} = local(instant, settings)
    sign = if offset < 0, do: "-", else: "+"
    hours = div(abs(offset), 3600) |> Integer.to_string() |> String.pad_leading(2, "0")
    minutes = div(rem(abs(offset), 3600), 60) |> Integer.to_string() |> String.pad_leading(2, "0")

    suffix =
      if utc,
        do: "Z",
        else: sign <> hours <> ":" <> minutes

    local |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601() |> Kernel.<>(suffix)
  end

  def query(value) do
    value
    |> to_string()
    |> then(&Regex.replace(~r/\A[\x00\t\n\x0B\f\r ]+|[\x00\t\n\x0B\f\r ]+\z/u, &1, ""))
    |> String.codepoints()
    |> Enum.take(100)
    |> Enum.join()
  end

  def search(value, locale \\ "en") do
    replacements = Dawarich.Achievements.Registry.approximations(locale)

    value
    |> String.codepoints()
    |> Enum.map(fn char ->
      if byte_size(char) == 1, do: char, else: Map.get(replacements, char, "?")
    end)
    |> Enum.join()
    |> String.downcase()
  end

  defp local(instant, settings), do: UserTimeZone.local(settings, DateTime.to_naive(instant))
end
