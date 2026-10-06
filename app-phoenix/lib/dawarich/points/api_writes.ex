defmodule Dawarich.Points.ApiWrites do
  @moduledoc false
  alias Dawarich.Imports.Api
  alias Dawarich.{I18n, RailsCommands, RubyInteger}
  alias Dawarich.MapApi.PointRecord
  @limit 5000

  def bulk_destroy(repo, user, params, ctx) do
    with :ok <- Api.guard(user, ctx) do
      ids = params["point_ids"]

      cond do
        not is_list(ids) or ids == [] or not Enum.all?(ids, &Dawarich.Ingest.Ruby.scalar?/1) ->
          error(422, "no_points_selected")

        length(ids) > @limit ->
          {:error, 422,
           Map.merge(
             message("error", "too_many_points_selected_maximum_is_bulk_destroy_max_per",
               limit: @limit
             ),
             %{"limit" => @limit, "requested" => length(ids)}
           )}

        true ->
          deleted = delete(repo, user, ids, ctx)

          {:ok, 200,
           Map.put(
             message("message", "points_were_successfully_destroyed"),
             "count",
             length(deleted)
           )}
      end
    end
  end

  def destroy(repo, user, id, ctx) do
    with :ok <- Api.guard(user, ctx), {:ok, _} <- identity(repo, user.id, id) do
      delete(repo, user, [id], ctx)
      {:ok, 200, message("message", "point_deleted_successfully")}
    end
  end

  def update(repo, user, id, params, ctx) do
    with :ok <- Api.guard(user, ctx),
         {:ok, point} <- identity(repo, user.id, id),
         {:ok, attrs} <- required(params, "point") do
      wkt =
        "POINT(#{Dawarich.Ingest.Ruby.to_s(attrs["longitude"])} #{Dawarich.Ingest.Ruby.to_s(attrs["latitude"])})"

      geometry = Dawarich.Ingest.Geo.ewkb!(wkt)

      {:ok, _} =
        repo.transaction(fn ->
          repo.query!(
            "UPDATE points SET lonlat=$2::text::geography,country_id=NULL,country_name=NULL,country=NULL,city=NULL,geodata='{}',reverse_geocoded_at=NULL,updated_at=now(),lock_version=lock_version+1 WHERE id=$1",
            [point.id, geometry]
          )

          country!(repo, point.id)

          RailsCommands.insert!(repo, "points.tile_epoch", %{
            "user_id" => user.id,
            "timestamps" => [point.timestamp]
          })

          RailsCommands.insert!(repo, "achievements.check", %{
            "user_id" => user.id,
            "oldest_timestamp" => point.timestamp
          })

          if Dawarich.Geocoding.Config.resolve(repo).enabled,
            do:
              produce(
                repo,
                "geocoding.reverse_point",
                %{"user_id" => user.id, "point_ids" => [point.id], "force" => true},
                user.id
              )

          if point.track_id,
            do:
              produce(repo, "tracks.recalculate", %{"track_id" => point.track_id}, point.track_id)
        end)

      try do
        Map.get(ctx, :after_commit, fn -> :ok end).()
        {:ok, 200, serialize(repo, point.id, params["slim"] == "true")}
      rescue
        _ -> {:error, 500, nil}
      end
    end
  rescue
    Dawarich.Ingest.Unsupported ->
      {:error, 422, %{"error" => "Lonlat can't be blank"}}

    error in Postgrex.Error ->
      if error.postgres[:code] == :unique_violation,
        do:
          {:error, 422,
           %{
             "error" =>
               "Lonlat " <>
                 I18n.en!("models.point.already_has_a_point_at_this_location_and_time_for")
           }},
        else: reraise(error, __STACKTRACE__)
  end

  def identity(repo, actor, id) do
    case repo.query!(
           "SELECT id,timestamp,track_id,lock_version FROM points WHERE user_id=$1 AND id=$2",
           [actor, RubyInteger.to_i(id)]
         ).rows do
      [[id, timestamp, track, revision]] ->
        {:ok, %{id: id, timestamp: timestamp, track_id: track, revision: revision}}

      _ ->
        Api.error(404, "controllers.api.record_not_found")
    end
  end

  def required(params, key) do
    case params[key] do
      value when is_map(value) and map_size(value) > 0 -> {:ok, value}
      _ -> {:error, 400, %{"error" => "param is missing or the value is empty: #{key}"}}
    end
  end

  def serialize(repo, id, slim? \\ false) do
    result =
      repo.query!(
        "SELECT " <>
          PointRecord.select_sql(slim?) <>
          " FROM points p" <> PointRecord.joins() <> "WHERE p.id=$1",
        [id]
      )

    row = Map.new(Enum.zip(result.columns, hd(result.rows)))
    {:ok, columns} = PointRecord.columns()
    PointRecord.term(row, columns, slim?)
  end

  def country!(repo, point) do
    repo.query!(
      "UPDATE points p SET country_id=c.id,country_name=c.name,country=c.name FROM countries c WHERE p.id=$1 AND c.id=(SELECT id FROM countries WHERE ST_Contains(geom,p.lonlat::geometry) ORDER BY id LIMIT 1)",
      [point]
    )
  end

  def produce(repo, kind, payload, aggregate) do
    case Dawarich.Jobs.Ownership.lock(repo, "command:" <> kind) do
      :oban ->
        repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),$1,1,$2,$3,$4,now())",
          [kind, payload, %{"producer" => "Phoenix Points API"}, aggregate]
        )

      :sidekiq when kind == "tracks.recalculate" ->
        RailsCommands.insert!(
          repo,
          "points.anomaly_recalculate",
          Map.merge(payload, %{"user_id" => owner(repo, aggregate), "job_queue" => nil})
        )

      :sidekiq ->
        RailsCommands.insert!(repo, kind, payload)
    end
  end

  defp owner(repo, track) do
    [[owner]] = repo.query!("SELECT user_id FROM tracks WHERE id=$1", [track]).rows
    owner
  end

  defp delete(repo, user, ids, _ctx) do
    ids = Enum.map(ids, &id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {:ok, rows} =
      repo.transaction(fn ->
        rows =
          repo.query!(
            "WITH deleted AS (DELETE FROM points WHERE user_id=$1 AND id=ANY($2::bigint[]) RETURNING id,timestamp,track_id,import_id) SELECT id,timestamp,track_id,import_id FROM deleted ORDER BY id",
            [user.id, ids]
          ).rows

        if rows != [] do
          repo.query!("UPDATE users SET points_count=COALESCE(points_count,0)-$2 WHERE id=$1", [
            user.id,
            length(rows)
          ])

          for {import, count} <-
                rows
                |> Enum.reject(&is_nil(Enum.at(&1, 3)))
                |> Enum.frequencies_by(&Enum.at(&1, 3)),
              do:
                repo.query!(
                  "UPDATE imports SET points_count=COALESCE(points_count,0)-$2 WHERE id=$1",
                  [import, count]
                )

          stamps = Enum.map(rows, &Enum.at(&1, 1))

          RailsCommands.insert!(repo, "points.web_destroy_follow_up", %{
            "user_id" => user.id,
            "timestamps" => stamps,
            "track_ids" =>
              rows |> Enum.map(&Enum.at(&1, 2)) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
            "oldest_timestamp" => Enum.min(stamps),
            "locale" => "en",
            "timezone" => Dawarich.UserTimeZone.iana(repo, user.settings)
          })
        end

        rows
      end)

    rows
  end

  defp id(value) when is_binary(value) do
    case Regex.run(~r/\A\s*([+-]?\d+)/, value, capture: :all_but_first) do
      [id] -> id(String.to_integer(id))
      _ -> nil
    end
  end

  defp id(value) when is_integer(value) and value >= 0 and value <= 9_223_372_036_854_775_807,
    do: value

  defp id(value) when is_float(value), do: id(trunc(value))

  defp id(_), do: nil
  defp error(status, key), do: {:error, status, message("error", key)}

  defp message(field, key, opts \\ []) do
    {:ok, text} =
      I18n.t(
        "en",
        "controllers.api.v1.points." <> key,
        Map.new(opts, fn {k, v} -> {to_string(k), v} end)
      )

    %{field => text}
  end
end
