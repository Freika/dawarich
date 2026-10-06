defmodule Dawarich.MapApi.Closure do
  @moduledoc false
  alias Dawarich.{MapApi, RailsTime, Repo, RubyInteger}
  alias Dawarich.AccountApi.Closure, as: Account
  alias Dawarich.MapApi.{Params, PointRecord, TrackRecord}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def read(action, user, params, now) do
    user = %{user | timezone: Account.zone(user.timezone)}

    RailsTime.with_zone(user.timezone, fn ->
      cutoff = window(user, now)

      case action do
        :points -> points(user, params, cutoff, now)
        :tracks when cutoff != nil -> tracks(user, params, cutoff)
        :track_points when cutoff != nil -> track_points(user, params, cutoff)
        :track when cutoff != nil -> track(user, params, cutoff, now)
        _ -> MapApi.read(action, user, params, now)
      end
    end)
    |> terminal()
  rescue
    _ -> {:error, 500}
  end

  def window(user, now) do
    if Account.full?(user, now) do
      nil
    else
      [[epoch]] =
        Repo.query!(
          "SELECT floor(extract(epoch FROM (($1::timestamptz AT TIME ZONE $2 - interval '12 months') AT TIME ZONE $2)))::bigint",
          [now, Account.zone(user.timezone)]
        ).rows

      epoch
    end
  end

  defp points(user, params, cutoff, now) do
    case MapApi.read(:points, user, points_params(params, cutoff, now), now) do
      {:points, term, headers, meta} when cutoff != nil ->
        end_value = if Ruby.present?(params["end_at"]), do: params["end_at"], else: {:now, now}
        {:ok, {from, to}} = Params.safe_range(params["start_at"], end_value, now)
        count = points_in_range(user.id, params, from, to)

        headers =
          headers ++
            [
              {"x-total-points-in-range", to_string(count)},
              {"x-scoped-points", to_string(meta.count)}
            ]

        {:points, term, headers, %{meta | from: from, to: to}}

      result ->
        result
    end
  end

  defp points_in_range(owner, params, from, to) do
    {where, args} =
      if from,
        do: {"user_id=$1 AND timestamp BETWEEN $2 AND $3", [owner, from, to]},
        else: {"user_id=$1 AND timestamp <= $2", [owner, to]}

    {where, args} =
      if Ruby.present?(params["import_id"]),
        do:
          {where <> " AND import_id=$#{length(args) + 1}",
           args ++ [RubyInteger.to_i(params["import_id"])]},
        else: {where, args}

    [[count]] = Repo.query!("SELECT count(*) FROM points WHERE " <> where, args).rows
    count
  end

  defp points_params(params, nil, _now), do: params

  defp points_params(params, cutoff, now) do
    {:ok, {from, _to}} = Params.safe_range(params["start_at"], params["end_at"], now)
    Map.put(params, "start_at", to_string(max(from || cutoff, cutoff)))
  end

  defp track(user, params, cutoff, now) do
    id = RubyInteger.to_i(params["id"])

    case TrackRecord.rows("WHERE t.user_id=$1 AND t.id=$2", [user.id, id]) do
      [] ->
        :missing

      [row] ->
        import? = Dawarich.ReleaseMigrations.Effects.Support.Ruby.present?(params["import_id"])

        {:ok, range} =
          if params["start_at"] not in [nil, ""] and params["end_at"] not in [nil, ""],
            do: Params.safe_range(params["start_at"], params["end_at"], now),
            else: {:ok, nil}

        clip? =
          import? or
            (range != nil and
               (trunc(Dawarich.MapApi.Segments.epoch(row["start_at"])) < elem(range, 0) or
                  trunc(Dawarich.MapApi.Segments.epoch(row["end_at"])) > elem(range, 1)))

        params =
          if clip? do
            {from, to} = range || {cutoff, 253_402_300_799}

            params
            |> Map.put("start_at", to_string(max(from, cutoff)))
            |> Map.put("end_at", to_string(to))
          else
            params
          end

        MapApi.read(:track, user, params, now)
    end
  end

  defp tracks(user, params, cutoff) do
    where = "WHERE t.user_id=$1 AND t.start_at >= (to_timestamp($2) AT TIME ZONE 'UTC')"
    args = [user.id, cutoff]

    {where, args} =
      if params["start_at"] && params["end_at"] do
        with {:ok, from} <- Params.zoned_time(params["start_at"]),
             {:ok, to} <- Params.zoned_time(params["end_at"]) do
          {where <>
             " AND t.end_at >= $3::text::timestamptz AT TIME ZONE 'UTC' AND t.start_at <= $4::text::timestamptz AT TIME ZONE 'UTC'",
           args ++ [from, to]}
        else
          _ -> {where, args}
        end
      else
        {where, args}
      end

    [[count]] = Repo.query!("SELECT count(*) FROM tracks t " <> where, args).rows
    page = Params.page(params["page"])
    per = Params.per_page(params["per_page"], 500)

    rows =
      TrackRecord.rows(
        where <> " ORDER BY t.start_at DESC LIMIT #{per} OFFSET #{(page - 1) * per}",
        args
      )

    {:ok,
     {:object, [{"type", "FeatureCollection"}, {"features", TrackRecord.features(rows, false)}]},
     [
       {"x-current-page", to_string(page)},
       {"x-total-pages", to_string(div(count + per - 1, per))},
       {"x-total-count", to_string(count)}
     ], 200}
  end

  defp track_points(user, params, cutoff) do
    id = RubyInteger.to_i(params["track_id"])

    case Repo.query!(
           "SELECT floor(extract(epoch FROM start_at))::bigint,floor(extract(epoch FROM end_at))::bigint FROM tracks WHERE user_id=$1 AND id=$2",
           [user.id, id]
         ).rows do
      [] ->
        :missing

      [[from, to]] ->
        [[associated]] =
          Repo.query!(
            "SELECT EXISTS(SELECT 1 FROM points WHERE track_id=$1 AND anomaly IS NOT TRUE)",
            [id]
          ).rows

        {where, args} =
          if associated,
            do:
              {"WHERE p.track_id=$1 AND p.timestamp >= $2 AND p.anomaly IS NOT TRUE",
               [id, cutoff]},
            else:
              {"WHERE p.user_id=$1 AND p.timestamp BETWEEN $2 AND $3 AND p.anomaly IS NOT TRUE",
               [user.id, max(from, cutoff), to]}

        {where, args} =
          if params["import_id"] in [nil, ""],
            do: {where, args},
            else:
              {where <> " AND p.import_id=$#{length(args) + 1}",
               args ++ [RubyInteger.to_i(params["import_id"])]}

        {suffix, headers} =
          if params["page"] in [nil, ""] do
            {"", []}
          else
            [[count]] = Repo.query!("SELECT count(*) FROM points p " <> where, args).rows
            page = Params.page(params["page"])
            per = Params.track_per_page(params["per_page"])

            {" LIMIT #{per} OFFSET #{(page - 1) * per}",
             [
               {"x-current-page", to_string(page)},
               {"x-total-pages", to_string(div(count + per - 1, per))}
             ]}
          end

        {:ok, columns} = PointRecord.columns()

        result =
          Repo.query!(
            "SELECT #{PointRecord.select_sql(false)} FROM points p " <>
              PointRecord.joins() <> where <> " ORDER BY p.timestamp ASC,p.id ASC" <> suffix,
            args
          )

        terms =
          Enum.map(result.rows, fn row ->
            PointRecord.term(Map.new(Enum.zip(result.columns, row)), columns, false)
          end)

        {:ok, terms, headers, 200}
    end
  end

  defp terminal({:replay, _}), do: {:error, 422}
  defp terminal(result), do: result
end
