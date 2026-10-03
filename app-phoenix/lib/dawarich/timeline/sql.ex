defmodule Dawarich.Timeline.Sql do
  @moduledoc false

  alias Dawarich.LocalTime

  def epoch(column), do: "floor(extract(epoch FROM #{column} AT TIME ZONE 'UTC'))::bigint"

  def local(column),
    do: "to_char(#{column} AT TIME ZONE 'UTC' AT TIME ZONE z.name, 'YYYY-MM-DD\"T\"HH24:MI:SS')"

  def offset(column),
    do: "extract(epoch FROM (#{column} AT TIME ZONE 'UTC' AT TIME ZONE z.name) - #{column})::int"

  def day(column), do: "(#{column} AT TIME ZONE 'UTC' AT TIME ZONE z.name)::date"

  def utc(param), do: "(to_timestamp(#{param}::bigint) AT TIME ZONE 'UTC')"

  def window_start(param),
    do:
      "(((#{param}::timestamptz AT TIME ZONE z.name) - interval '12 months') AT TIME ZONE z.name)"

  def windowed(column, param),
    do:
      "(#{param}::timestamptz IS NULL OR #{column} >= #{window_start(param)} AT TIME ZONE 'UTC')"

  def total(track), do: "extract(epoch FROM #{track}.end_at - #{track}.start_at)::float8"

  def shares(track) do
    next_midnight = "((d + interval '1 day') AT TIME ZONE z.name) AT TIME ZONE 'UTC'"
    midnight = "(d AT TIME ZONE z.name) AT TIME ZONE 'UTC'"
    upper = "least(#{track}.end_at, #{next_midnight})"
    lower = "greatest(#{track}.start_at, #{midnight})"

    """
    LEFT JOIN LATERAL (
      SELECT d::date AS day, extract(epoch FROM #{upper} - #{lower})::float8 AS seconds
      FROM generate_series(date_trunc('day', #{track}.start_at AT TIME ZONE 'UTC' AT TIME ZONE z.name),
                           #{track}.end_at AT TIME ZONE 'UTC' AT TIME ZONE z.name, interval '1 day') AS d
      WHERE #{upper} > #{lower}
    ) s ON true
    """
  end

  def iso(local, offset, zone), do: local <> LocalTime.offset(zone, offset, :iso)

  def shares_of(total, _start_day, slices) when total > 0,
    do: for({day, seconds} <- slices, do: {day, seconds / total})

  def shares_of(_total, start_day, _slices), do: [{start_day, 1.0}]
end
