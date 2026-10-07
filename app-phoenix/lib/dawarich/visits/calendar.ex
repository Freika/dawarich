defmodule Dawarich.Visits.Calendar do
  @moduledoc false

  def changed(repo, user_id, stamps) do
    payload = %{
      "user_id" => user_id,
      "started_at" => stamps |> Enum.map(&DateTime.to_iso8601/1) |> Enum.uniq()
    }

    if Dawarich.Standalone.enabled?() or
         Dawarich.Jobs.Ownership.lock(repo, "command:visits.suggest") == :oban,
       do: Dawarich.AfterCommit.enqueue(repo, Dawarich.Points.VisitMonthsWorker, payload),
       else:
         Dawarich.AfterCommit.with_visibility(repo, "visit_months", payload, fn ->
           Dawarich.RailsCommands.insert!(repo, "visit_months_changed", payload)
         end)
  end

  def invalidate(repo, user, stamps) do
    setting = Dawarich.UserSettings.get(user)["timezone"] || System.get_env("TIME_ZONE", "UTC")
    setting = if setting == "", do: "UTC", else: setting
    zone = Dawarich.TimeZoneName.to_iana(setting)

    months =
      repo.query!(
        "SELECT DISTINCT to_char(stamp AT TIME ZONE $2, 'YYYY-MM') FROM unnest($1::timestamptz[]) stamp",
        [stamps, zone],
        log: false
      ).rows
      |> List.flatten()

    for month <- months, segment <- ~w(lite pro) do
      key = Enum.join(["timeline_month_summary", user.id, month, setting, segment, "v3"], "/")
      {:ok, _} = Dawarich.Redis.cache_command(["UNLINK", key])
    end

    :ok
  end

  @series "FROM generate_series(date_trunc('month', to_timestamp($1::bigint)), " <>
            "to_timestamp($2::bigint) - interval '1 second', interval '1 month') AS m ORDER BY m"

  def next_day(_repo, _zone, ts, "fixed"), do: ts + 86_400

  def next_day(repo, zone, ts, "calendar"),
    do:
      repo
      |> in_zone(
        zone,
        "SELECT floor(extract(epoch FROM to_timestamp($1::bigint) + interval '1 day'))::bigint",
        [ts]
      )
      |> hd()
      |> hd()

  def year_ago(repo, zone),
    do:
      repo
      |> in_zone(
        zone,
        "SELECT floor(extract(epoch FROM now() - interval '12 months'))::bigint",
        []
      )
      |> hd()
      |> hd()

  def month_batches(repo, zone, start, stop),
    do:
      in_zone(
        repo,
        zone,
        "SELECT greatest(extract(epoch FROM m)::bigint, $1::bigint), " <>
          "least(extract(epoch FROM m + interval '1 month')::bigint - 1, $2::bigint) " <> @series,
        [start, stop]
      )

  def redetect_months(repo, zone, min, max),
    do:
      in_zone(
        repo,
        zone,
        "SELECT greatest(extract(epoch FROM m)::bigint, $1::bigint), " <>
          "least(extract(epoch FROM m + interval '1 month')::bigint - 1 + 3600, $2::bigint) " <>
          @series,
        [min, max]
      )

  def previous_day(repo, zone, slot) do
    [[start, stop]] =
      in_zone(
        repo,
        zone,
        """
        SELECT to_char(date_trunc('day', to_timestamp($1::bigint)) - interval '1 day',
          'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
          to_char(date_trunc('day', to_timestamp($1::bigint)) - interval '1 microsecond',
          'YYYY-MM-DD"T"HH24:MI:SS.USTZH:TZM')
        """,
        [slot]
      )

    {start, stop}
  end

  def time_chunks(start, stop) do
    {:ok, first, offset} = DateTime.from_iso8601(start)
    {:ok, last, end_offset} = DateTime.from_iso8601(stop)
    first_year = first |> DateTime.to_naive() |> NaiveDateTime.add(offset) |> Map.fetch!(:year)
    last_year = last |> DateTime.to_naive() |> NaiveDateTime.add(end_offset) |> Map.fetch!(:year)
    a = DateTime.to_unix(first)
    b = DateTime.to_unix(last)

    if a >= b or first_year == last_year do
      [{a, b}]
    else
      [{a, year_start(first_year + 1, offset) - 1}] ++
        Enum.map((first_year + 1)..last_year, fn year ->
          {year_start(year, offset),
           if(year == last_year, do: b, else: year_start(year + 1, offset) - 1)}
        end)
    end
  end

  defp year_start(year, offset),
    do:
      NaiveDateTime.diff(NaiveDateTime.new!(year, 1, 1, 0, 0, 0), ~N[1970-01-01 00:00:00]) -
        offset

  defp in_zone(repo, zone, sql, params) do
    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('TimeZone', $1, true)", [zone], log: false)
        repo.query!(sql, params, log: false).rows
      end)

    rows
  end
end
