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

  def batch(repo, kind, period, after_id \\ 0) do
    month = if kind in [:monthly, "monthly"], do: period.month

    rows =
      repo.query!(
        "SELECT u.id, u.settings FROM public.users u " <>
          "WHERE u.id > $1 AND u.deleted_at IS NULL AND u.status IN (1, 2) " <>
          "AND EXISTS (SELECT 1 FROM public.stats s WHERE s.user_id = u.id " <>
          "AND s.year = $2 AND ($3::integer IS NULL OR s.month = $3)) " <>
          "ORDER BY u.id LIMIT 1000",
        [after_id, period.year, month],
        log: false
      ).rows

    key = to_string(kind) <> "_digest_emails_enabled"
    users = Enum.map(rows, fn [id, settings] -> %{id: id, settings: settings} end)
    eligible = Enum.filter(users, &Dawarich.UserSettings.digest?(&1, key))
    cursor = if rows != [], do: rows |> List.last() |> hd()
    {eligible, cursor}
  end
end
