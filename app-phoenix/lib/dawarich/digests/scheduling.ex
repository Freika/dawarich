defmodule Dawarich.Digests.Scheduling do
  @moduledoc false

  alias Dawarich.TimeZoneName

  def period(repo, kind, now, zone \\ System.get_env("TIME_ZONE", "Europe/Berlin")) do
    months = if kind in [:monthly, "monthly"], do: 1, else: 12

    %{rows: [[year, month]]} =
      repo.query!(
        "SELECT EXTRACT(year FROM target)::integer, EXTRACT(month FROM target)::integer " <>
          "FROM (SELECT ($1::timestamptz AT TIME ZONE $2) - $3::interval AS target) x",
        [now, TimeZoneName.to_iana(zone), %Postgrex.Interval{months: months}],
        log: false
      )

    %{year: year, month: if(months == 1, do: month)}
  end
end
