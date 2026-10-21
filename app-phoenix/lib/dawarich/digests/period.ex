defmodule Dawarich.Digests.Period do
  @moduledoc false

  alias Dawarich.Digests.Context
  alias Dawarich.RubyInteger

  def monthly(repo, context, year, month) do
    zone =
      context.user_zone || raise(ArgumentError, "Invalid Timezone: #{context.effective_zone}")

    bounds(repo, context, RubyInteger.to_i(year), RubyInteger.to_i(month), zone)
  end

  def yearly(repo, context, year),
    do: bounds(repo, context, RubyInteger.to_i(year), nil, context.ambient_zone)

  defp bounds(repo, context, year, month, zone) do
    first = date!(year, month || 1)
    next = if month, do: first |> Date.end_of_month() |> Date.add(1), else: date!(year + 1, 1)
    from = NaiveDateTime.new!(first, ~T[00:00:00])
    until = NaiveDateTime.new!(next, ~T[00:00:00])

    %{rows: [[first_epoch, last_epoch, first_time, last_time]]} =
      repo.query!(
        "SELECT extract(epoch FROM ($1::timestamp AT TIME ZONE $3))::bigint, " <>
          "extract(epoch FROM ($2::timestamp AT TIME ZONE $3))::bigint - 1, " <>
          "($1::timestamp AT TIME ZONE $3) AT TIME ZONE 'UTC', " <>
          "(($2::timestamp AT TIME ZONE $3) - interval '1 microsecond') AT TIME ZONE 'UTC'",
        [from, until, zone],
        log: false
      )

    context = Context.window(repo, context, zone)

    %{
      year: year,
      month: month,
      zone: zone,
      first: first_epoch,
      last: last_epoch,
      from: first_time,
      until: last_time,
      context: context,
      location_first:
        if(is_nil(month) and context.point_cutoff,
          do: max(first_epoch, context.point_cutoff),
          else: first_epoch
        )
    }
  end

  defp date!(year, month) do
    case Date.new(year, month, 1) do
      {:ok, date} -> date
      {:error, _} -> raise ArgumentError, "mon out of range"
    end
  end
end
