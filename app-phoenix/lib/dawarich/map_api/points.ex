defmodule Dawarich.MapApi.Points do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo, RubyInteger}
  alias Dawarich.MapApi.{Params, PointRecord}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @bbox ~w(min_longitude max_longitude min_latitude max_latitude)
  @kept "(p.anomaly = false OR p.anomaly IS NULL)"

  def index(user, params, now) do
    end_value = if Ruby.present?(params["end_at"]), do: params["end_at"], else: {:now, now}

    with {:ok, {from, to}} <- Params.safe_range(params["start_at"], end_value, now),
         {:ok, columns} <- PointRecord.columns(),
         {:ok, where, args} <- filter(user.id, from, to, params),
         {:ok, order} <- order(params["order"]) do
      [[count, max_timestamp, max_updated]] =
        Repo.query!(
          "SELECT COUNT(*), MAX(p.timestamp), MAX(p.updated_at) FROM points p " <> where,
          args
        ).rows

      page = Params.page(params["page"])
      per = params["per_page"] |> Params.per_page(100) |> min(10_000)
      slim? = params["slim"] == "true"
      sql = where <> " ORDER BY p.timestamp #{order} LIMIT #{per} OFFSET #{(page - 1) * per}"

      term = fn ->
        RailsTime.with_zone(user.timezone, fn ->
          Enum.map(rows(sql, args), &PointRecord.term(&1, columns, slim?))
        end)
      end

      headers = [
        {"x-current-page", Integer.to_string(page)},
        {"x-total-pages", Integer.to_string(div(count + per - 1, per))}
      ]

      meta = %{
        from: from,
        to: to,
        count: count,
        max_timestamp: max_timestamp,
        max_updated: max_updated
      }

      {:points, term, headers, meta}
    end
  end

  def track(user, params) do
    id = RubyInteger.to_i(params["track_id"])

    case Repo.query!(
           "SELECT floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint " <>
             "FROM tracks WHERE user_id = $1 AND id = $2",
           [user.id, id]
         ).rows do
      [] -> :missing
      [[from, to]] -> track_points(user, id, from, to, params)
    end
  end

  defp track_points(user, id, from, to, params) do
    with {:ok, columns} <- PointRecord.columns() do
      [[associated?]] =
        Repo.query!("SELECT EXISTS(SELECT 1 FROM points p WHERE p.track_id = $1 AND #{@kept})", [
          id
        ]).rows

      {where, args} =
        if associated?,
          do: {"WHERE p.track_id = $1 AND #{@kept}", [id]},
          else:
            {"WHERE p.user_id = $1 AND p.timestamp BETWEEN $2::bigint AND $3::bigint AND #{@kept}",
             [user.id, from, to]}

      {where, args} = import(where, args, params["import_id"])
      {suffix, headers} = paginate(where, args, params)
      sql = where <> " ORDER BY p.timestamp ASC, p.id ASC" <> suffix
      {:ok, Enum.map(rows(sql, args), &PointRecord.term(&1, columns, false)), headers, 200}
    end
  end

  defp rows(where, args) do
    result =
      Repo.query!(
        "SELECT #{PointRecord.select_sql()} FROM points p " <> PointRecord.joins() <> where,
        args
      )

    Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
  end

  defp paginate(where, args, params) do
    if Ruby.present?(params["page"]) do
      [[count]] = Repo.query!("SELECT COUNT(*) FROM points p " <> where, args).rows
      page = Params.page(params["page"])
      per = Params.track_per_page(params["per_page"])

      {" LIMIT #{per} OFFSET #{(page - 1) * per}",
       [
         {"x-current-page", Integer.to_string(page)},
         {"x-total-pages", Integer.to_string(div(count + per - 1, per))}
       ]}
    else
      {"", []}
    end
  end

  defp order(value) when value in [nil, "asc", "desc", "ASC", "DESC"],
    do: {:ok, String.upcase(value || "desc")}

  defp order(_value), do: {:replay, "point order"}

  defp filter(user_id, from, to, params) do
    {where, args} =
      if from,
        do:
          {"WHERE p.user_id = $1 AND p.timestamp BETWEEN $2::bigint AND $3::bigint",
           [user_id, from, to]},
        else: {"WHERE p.user_id = $1 AND p.timestamp <= $2::bigint", [user_id, to]}

    where =
      cond do
        Params.boolean(params["anomalies_only"]) -> where <> " AND p.anomaly = true"
        Params.boolean(params["include_anomalies"]) -> where
        true -> where <> " AND " <> @kept
      end

    {where, args} = import(where, args, params["import_id"])

    if Enum.all?(@bbox, &Ruby.present?(params[&1])),
      do: bbox(where, args, Enum.map(@bbox, &params[&1])),
      else: {:ok, where, args}
  end

  defp bbox(where, args, values) do
    case Params.bbox(values) do
      {:ok, corners} ->
        at = length(args)
        envelope = "ST_MakeEnvelope($#{at + 1}, $#{at + 2}, $#{at + 3}, $#{at + 4}, 4326)"

        {:ok,
         where <>
           " AND p.lonlat && #{envelope}::geography AND ST_Intersects(p.lonlat::geometry, #{envelope})",
         args ++ corners}

      :error ->
        :bad_bbox
    end
  end

  defp import(where, args, value) do
    if Ruby.present?(value),
      do: {where <> " AND p.import_id = $#{length(args) + 1}", args ++ [RubyInteger.to_i(value)]},
      else: {where, args}
  end
end
