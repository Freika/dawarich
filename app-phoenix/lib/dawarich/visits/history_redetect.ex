defmodule Dawarich.Visits.HistoryRedetect do
  @moduledoc false

  alias Dawarich.Visits.{Persister, VisitRescore}

  @batch_size 200

  def cooldown?(nil, _now), do: false

  def cooldown?(last, now),
    do: NaiveDateTime.compare(last, DateTime.to_naive(DateTime.add(now, -3600))) == :gt

  def enqueue(repo, user_id, settings, last, now, locale, opts \\ []) do
    owner =
      Keyword.get_lazy(opts, :owner, fn ->
        Dawarich.Jobs.Ownership.lock(repo, "command:visits.full_history_redetect")
      end)

    if cooldown?(last, now),
      do: repo.rollback(if(owner == :oban, do: {:cooldown, 429, :native}, else: {:cooldown, 429}))

    zone = settings["timezone"] || Dawarich.UserTimeZone.zone(%{})

    unless is_binary(zone) and
             repo.query!(
               "SELECT 1 FROM pg_timezone_names WHERE name=$1",
               [Dawarich.TimeZoneName.to_iana(zone)],
               log: false
             ).num_rows == 1,
           do: repo.rollback({:replay, "visit time zone"})

    if owner == :sidekiq do
      Dawarich.RailsCommands.insert!(repo, "visits.web_redetect", %{
        "user_id" => user_id,
        "locale" => locale,
        "timezone" => Dawarich.TimeZoneName.to_iana(zone)
      })
    else
      [[plan]] = repo.query!("SELECT plan FROM users WHERE id=$1", [user_id], log: false).rows
      user = %{id: user_id, plan: plan}

      restricted =
        not Dawarich.Entitlements.full_access?(
          repo,
          user,
          DawarichWeb.LayoutAssigns.self_hosted?(),
          now
        )

      payload = %{
        "user_id" => user_id,
        "time_zone" => Dawarich.TimeZoneName.to_iana(zone),
        "plan_restricted" => restricted
      }

      repo.query!(
        "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,'visits.full_history_redetect',1,$2,$3,$4,$5)",
        [
          Ecto.UUID.bingenerate(),
          payload,
          %{"producer" => "Visits::FullHistoryRedetectJob", "locale" => locale},
          user_id,
          now
        ],
        log: false
      )

      :ok
    end
  end

  @legacy_sql "SELECT id, floor(extract(epoch FROM started_at))::bigint, floor(extract(epoch FROM ended_at))::bigint, " <>
                "area_id, place_id FROM visits WHERE user_id = $1 AND deleted_at IS NULL AND status != 2 " <>
                "AND confidence IS NULL AND id > $2 ORDER BY id LIMIT #{@batch_size}"

  @points_sql "SELECT visit_id, id, accuracy, ST_Y(lonlat::geometry), ST_X(lonlat::geometry) FROM points " <>
                "WHERE visit_id = ANY($1) ORDER BY id"

  def purge(repo, user_id, nil, nil), do: wipe(repo, user_id, "TRUE", [user_id])

  def purge(repo, user_id, min_ts, max_ts),
    do:
      wipe(repo, user_id, "NOT (v.started_at <= $2 AND v.ended_at >= $3)", [
        user_id,
        naive(max_ts),
        naive(min_ts)
      ])

  def backfill(repo, user_id, policy, after_id \\ 0) do
    visits =
      for [id, from, to, area_id, place_id] <-
            repo.query!(@legacy_sql, [user_id, after_id], log: false).rows,
          do: %{id: id, started_at: from, ended_at: to, area_id: area_id, place_id: place_id}

    if visits != [] do
      points =
        repo.query!(@points_sql, [Enum.map(visits, & &1.id)], log: false).rows
        |> Enum.group_by(&hd/1, fn [_, id, accuracy, lat, lon] ->
          %{id: id, accuracy: accuracy, lat: lat, lon: lon}
        end)

      Enum.each(visits, &VisitRescore.run(repo, &1, policy, Map.get(points, &1.id, [])))
      if length(visits) == @batch_size, do: backfill(repo, user_id, policy, List.last(visits).id)
    end

    :ok
  end

  defp wipe(repo, user_id, condition, params) do
    {:ok, rows} = repo.transaction(fn -> Persister.wipe(repo, user_id, condition, params) end)
    length(rows)
  end

  defp naive(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_naive()
end
