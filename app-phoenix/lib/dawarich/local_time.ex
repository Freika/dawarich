defmodule Dawarich.LocalTime do
  @moduledoc false

  alias Dawarich.{Repo, UserTimeZone}

  @utc ~w(UTC Etc/UTC UCT Etc/UCT Universal Etc/Universal Zulu Etc/Zulu)

  def local(settings, now, env \\ System.get_env()) do
    %{rows: [[zone, today]]} =
      UserTimeZone.query!(
        "SELECT z.name, ($1::timestamptz AT TIME ZONE z.name)::date FROM z",
        [now],
        settings,
        env
      )

    {zone, today}
  end

  def day_bounds(zone, date) do
    %{rows: [[first, last]]} =
      Repo.query!(
        """
        SELECT extract(epoch FROM (d - (d AT TIME ZONE $2 AT TIME ZONE 'UTC')))::int,
               extract(epoch FROM (e - (e AT TIME ZONE $2 AT TIME ZONE 'UTC')))::int
        FROM (SELECT $1::date::timestamp AS d, $1::date + time '23:59:59' AS e) t
        """,
        [date, zone]
      )

    day = Date.to_iso8601(date)
    {"#{day} 00:00:00 #{offset(zone, first)}", "#{day} 23:59:59 #{offset(zone, last)}"}
  end

  def offset(zone, seconds, format \\ :db)
  def offset(zone, 0, :db) when zone in @utc, do: "UTC"
  def offset(zone, 0, :iso) when zone in @utc, do: "Z"

  def offset(_zone, seconds, format) do
    sign = if seconds < 0, do: "-", else: "+"
    minutes = div(abs(seconds), 60)
    hh = pad(div(minutes, 60))
    mm = pad(rem(minutes, 60))
    if format == :iso, do: sign <> hh <> ":" <> mm, else: sign <> hh <> mm
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
