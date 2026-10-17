defmodule Dawarich.Points.ApiPosition do
  @moduledoc false
  alias Dawarich.Imports.Api
  alias Dawarich.Points.ApiWrites
  alias Dawarich.RubyInteger
  alias Dawarich.Metrics.Map, as: Metrics
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def update(repo, user, id, params, ctx) do
    with :ok <- Api.guard(user, ctx),
         {:ok, attrs} <- ApiWrites.required(params, "point"),
         {:ok, scope} <- ApiWrites.required(params, "history_scope"),
         {:ok, scope} <- history(scope, user, repo),
         {:ok, lat, lon, revision, track_revision} <- coordinates(attrs, params) do
      Metrics.move(fn ->
        result =
          repo.transaction(fn ->
            move(repo, user, id, lat, lon, revision, track_revision, scope)
          end)

        case result do
          {:ok, {:ok, response, point, measurements}} ->
            Dawarich.Points.PositionEffects.call(repo, user, point, response)
            {"success", measurements, {:ok, 200, response}}

          {:error, {:stale, response, measurements}} ->
            {"conflict", measurements, {:error, 409, stale(response)}}

          {:error, {:stale, response}} ->
            {"conflict", Metrics.sizes(repo, nil), {:error, 409, stale(response)}}

          {:error, {:timeout, lock_wait}} ->
            {"timeout", Map.put(Metrics.sizes(repo, nil), :lock_wait, lock_wait),
             invalid("recalculation_timeout", "canceling statement due to statement timeout")}

          {:ok, error} ->
            {nil, %{}, error}
        end
      end)
    end
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :query_canceled,
        do: invalid("recalculation_timeout", "canceling statement due to statement timeout"),
        else: reraise(error, __STACKTRACE__)

    Dawarich.Tracks.Invalid ->
      invalid("invalid_edit", "Validation failed: ")
  end

  defp move(repo, user, id, lat, lon, revision, track_revision, scope) do
    repo.query!("SET LOCAL statement_timeout='3s'")

    with {:ok, identity} <- ApiWrites.identity(repo, user.id, id) do
      locks_started = System.monotonic_time()
      track = lock_track(repo, user.id, identity.track_id)

      repo.query!("SELECT id FROM points WHERE id=$1 AND user_id=$2 FOR UPDATE", [
        identity.id,
        user.id
      ])

      lock_wait = System.monotonic_time() - locks_started

      try do
        {:ok, point} = ApiWrites.identity(repo, user.id, id)

        if point.track_id != identity.track_id or point.revision != revision or
             (track && track.revision != track_revision),
           do:
             repo.rollback(
               {:stale, response(repo, point, track, nil),
                Map.put(Metrics.sizes(repo, track), :lock_wait, lock_wait)}
             )

        before = countries(repo, user.id, scope)

        repo.query!(
          "UPDATE points SET lonlat=ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,country_id=NULL,country_name=NULL,country=NULL,city=NULL,reverse_geocoded_at=NULL,lock_version=lock_version+1,updated_at=now() WHERE id=$1",
          [point.id, lon, lat]
        )

        ApiWrites.country!(repo, point.id)

        if track do
          [[previous]] =
            repo.query!("SELECT COALESCE(max(id),0) FROM phoenix.rails_commands").rows

          Dawarich.Tracks.Recalculator.call(repo, Dawarich.Tracks.Store.get(repo, track.id))

          repo.query!(
            "DELETE FROM phoenix.rails_commands WHERE id>$1 AND kind='tracks_changed' AND payload->>'user_id'=$2",
            [previous, to_string(user.id)]
          )
        end

        after_countries = countries(repo, user.id, scope)
        visited = if before == after_countries, do: nil, else: %{"iso_a3" => after_countries}
        {:ok, point} = ApiWrites.identity(repo, user.id, point.id)
        track = lock_track(repo, user.id, identity.track_id)
        measurements = Map.put(Metrics.sizes(repo, track, true), :lock_wait, lock_wait)
        {:ok, response(repo, point, track, visited), point, measurements}
      rescue
        error in Postgrex.Error ->
          if error.postgres[:code] == :query_canceled,
            do: repo.rollback({:timeout, lock_wait}),
            else: reraise(error, __STACKTRACE__)
      end
    end
  end

  defp lock_track(_repo, _actor, nil), do: nil

  defp lock_track(repo, actor, id) do
    case repo.query!("SELECT id,lock_version FROM tracks WHERE user_id=$1 AND id=$2 FOR UPDATE", [
           actor,
           id
         ]).rows do
      [[id, revision]] -> %{id: id, revision: revision}
      [] -> repo.rollback({:stale, {:object, []}})
    end
  end

  defp response(repo, point, track, countries) do
    feature = if track, do: track.id |> feature()

    {:object,
     [
       {"point", ApiWrites.serialize(repo, point.id)},
       {"track", feature},
       {"revision", %{"point" => point.revision, "track" => track && track.revision}},
       {"visited_countries", countries}
     ]}
  end

  defp feature(track) do
    [feature] =
      Dawarich.MapApi.TrackRecord.rows("WHERE t.id=$1", [track])
      |> Dawarich.MapApi.TrackRecord.features(true)

    feature
  end

  defp stale({:object, fields}), do: {:object, fields ++ [{"error", %{"code" => "stale_edit"}}]}

  defp countries(repo, actor, scope) do
    repo.query!(
      "SELECT DISTINCT c.iso_a3,COALESCE(c.name,NULLIF(p.country_name,''),NULLIF(p.country,'')) FROM points p LEFT JOIN countries c ON c.id=p.country_id WHERE p.user_id=$1 AND p.anomaly IS NOT TRUE AND p.timestamp BETWEEN $2 AND $3 AND ($4::bigint IS NULL OR p.import_id=$4)",
      [actor, scope.start, scope.end, scope.import]
    ).rows
    |> Enum.map(fn [code, name] -> code || elem(Dawarich.CountryNames.iso_codes(name), 1) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp history(scope, user, repo) do
    zone = Dawarich.UserTimeZone.name(Dawarich.UserSettings.get(user), repo)

    with {:ok, start} <- timestamp(scope["start_at"], zone, repo),
         {:ok, stop} <- timestamp(scope["end_at"], zone, repo),
         true <- start <= stop do
      {:ok,
       %{
         start: start,
         end: stop,
         import:
           if(Ruby.blank?(scope["import_id"]),
             do: nil,
             else: RubyInteger.to_i(scope["import_id"])
           )
       }}
    else
      _ -> invalid("invalid_edit", "Points::Move::InvalidHistoryScope")
    end
  end

  defp timestamp(value, _zone, _repo) when is_integer(value) and value >= 0, do: {:ok, value}

  defp timestamp(value, zone, repo) when is_binary(value) do
    if value =~ ~r/\A\d+\z/ do
      {:ok, String.to_integer(value)}
    else
      value = Regex.replace(~r/(T\d{2}:\d{2})(Z|[+-]\d{2}:\d{2})?\z/, value, "\\1:00\\2")

      case DateTime.from_iso8601(value) do
        {:ok, date, _} -> {:ok, DateTime.to_unix(date)}
        _ -> local_timestamp(value, zone, repo)
      end
    end
  end

  defp timestamp(_, _zone, _repo), do: :error

  defp local_timestamp(value, zone, repo) do
    value = if value =~ ~r/\A\d{4}-\d{2}-\d{2}\z/, do: value <> "T00:00:00", else: value

    with {:ok, date} <- NaiveDateTime.from_iso8601(value) do
      [[epoch]] =
        repo.query!("SELECT extract(epoch FROM $1::timestamp AT TIME ZONE $2)::bigint", [
          date,
          zone
        ]).rows

      {:ok, epoch}
    else
      _ -> :error
    end
  end

  defp coordinates(attrs, params) do
    with lat when is_number(lat) and lat >= -90 and lat <= 90 <- float(attrs["latitude"]),
         lon when is_number(lon) and lon >= -180 and lon <= 180 <- float(attrs["longitude"]),
         {:ok, revision} <- revision(attrs["revision"]),
         {:ok, track} <- revision(params["track_revision"], true) do
      {:ok, lat * 1.0, lon * 1.0, revision, track}
    else
      _ -> invalid("invalid_edit", "Points::Move::InvalidCoordinates")
    end
  end

  defp float(value) when is_number(value), do: value
  defp float(value) when is_binary(value), do: Ruby.float(value)
  defp float(_), do: nil
  defp revision(value, optional \\ false)
  defp revision(nil, true), do: {:ok, nil}
  defp revision(value, _) when is_integer(value), do: {:ok, value}
  defp revision(value, _) when is_float(value), do: {:ok, trunc(value)}

  defp revision(value, _) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp revision(_, _), do: :error

  defp invalid(code, message),
    do: {:error, 422, %{"error" => %{"code" => code, "message" => message}}}
end
