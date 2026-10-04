defmodule Dawarich.PointListWindow do
  @moduledoc false

  alias Dawarich.{MapWindow, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @defaults """
  SELECT to_char(date_trunc('day', CASE WHEN $2::bigint IS NULL
           THEN (($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE z.name) - interval '1 month'
           ELSE to_timestamp($2) AT TIME ZONE z.name END), 'YYYY-MM-DD"T"HH24:MI:SS'),
         to_char(date_trunc('day', CASE WHEN $3::bigint IS NULL
           THEN ($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE z.name
           ELSE to_timestamp($3) AT TIME ZONE z.name END) + interval '1 day' - interval '1 second',
           'YYYY-MM-DD"T"HH24:MI:SS')
  FROM z
  """

  def build(params, settings, now, range) do
    {first, last} = range || {nil, nil}

    [[start_value, end_value]] =
      UserTimeZone.query!(@defaults, [DateTime.to_naive(now), first, last], settings).rows

    if supported_default?(params["start_at"], start_value) and
         supported_default?(params["end_at"], end_value) do
      supplied = Map.filter(params, fn {_key, value} -> Ruby.present?(value) end)
      values = Map.merge(%{"start_at" => start_value, "end_at" => end_value}, supplied)
      window = MapWindow.build(values, settings, now, nil)
      Map.merge(window, %{start_epoch: epoch(window.start), end_epoch: epoch(window.end)})
    else
      :rails
    end
  end

  defp supported_default?(supplied, value),
    do:
      Ruby.present?(supplied) or
        (value >= "1970-01-01T00:00:00" and value <= "2100-01-01T00:00:00")

  defp epoch(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    DateTime.to_unix(datetime)
  end
end
