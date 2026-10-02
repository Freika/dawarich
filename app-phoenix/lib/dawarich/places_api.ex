defmodule Dawarich.PlacesApi do
  @moduledoc false

  alias Dawarich.{I18n, PlaceCascade, RailsTime, Repo}
  alias Dawarich.PlacesApi.{Index, Payload}

  @sources %{"manual" => 0, "photon" => 1, "gpx_waypoint" => 2}
  @attributes ~w(name latitude longitude source note)
  @placeholder "Suggested place"
  @point "ST_SetSRID(ST_MakePoint($4::float8, $3::float8), 4326)::geography"
  @lookup "SELECT id, name, latitude::float8, longitude::float8, source, note, name_locked_at, " <>
            "COALESCE(ST_Y(lonlat::geometry) = latitude::float8 " <>
            "AND ST_X(lonlat::geometry) = longitude::float8, false) " <>
            "FROM places WHERE id = $1 AND user_id = $2 FOR UPDATE"
  @insert "INSERT INTO places (user_id, name, latitude, longitude, source, note, name_locked_at, " <>
            "lonlat, created_at, updated_at) VALUES ($1, $2, $3::float8, $4::float8, $5, $6, $7, " <>
            "#{@point}, $8, $8) RETURNING id"
  @update "UPDATE places SET name = $2, latitude = $3::float8, longitude = $4::float8, " <>
            "source = $5, note = $6, name_locked_at = $7, lonlat = #{@point}, updated_at = $8 " <>
            "WHERE id = $1"

  def run(action, user, params, now) do
    RailsTime.with_zone(user.timezone, fn ->
      dispatch(action, user.id, params, DateTime.to_naive(now))
    end)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp dispatch(:index, owner, params, _now), do: Index.read(owner, params)

  defp dispatch(:create, owner, params, now) do
    if inputs?(params["place"]),
      do: save(owner, nil, params["place"], now),
      else: {:replay, "place parameters"}
  end

  defp dispatch(action, owner, %{"id" => text} = params, now) do
    case Integer.parse(text) do
      {id, ""} when id >= 0 -> member(action, owner, id, params, now)
      _ -> {:replay, "place id"}
    end
  end

  defp member(:show, owner, id, _params, _now) do
    case Payload.places(owner, "p.id = $2", [id]) do
      [term] -> {:ok, 200, term, []}
      [] -> not_found()
    end
  end

  defp member(action, owner, id, params, now) do
    case Repo.query!(@lookup, [id, owner]).rows do
      [] -> not_found()
      [row] -> change(action, owner, row, params["place"], now)
    end
  end

  defp change(:destroy, _owner, [id | _], _changes, _now) do
    PlaceCascade.delete!(Repo, [id])
    :no_content
  end

  defp change(:update, owner, [_, name, _, _, _, note, _, coherent] = row, changes, now) do
    cond do
      not inputs?(changes) ->
        {:replay, "place parameters"}

      not (coherent and ascii?(name) and ascii?(note)) ->
        {:replay, "legacy place geometry or text"}

      Enum.any?(~w(latitude longitude), &(Map.has_key?(changes, &1) and changes[&1] == nil)) ->
        {:replay, "null coordinate on update"}

      true ->
        save(owner, row, changes, now)
    end
  end

  defp save(owner, previous, changes, now) do
    attrs = Map.merge(stored(previous), Map.take(changes, @attributes))
    name = attrs["name"]
    values = [name, number(attrs["latitude"]), number(attrs["longitude"])]
    source = Map.get(@sources, attrs["source"], attrs["source"])
    values = values ++ [source, attrs["note"]]

    case errors(values) do
      [] -> write(owner, previous, values ++ [lock(previous, name, now), now])
      errors -> {:ok, 422, {:object, [{"errors", errors}]}, []}
    end
  end

  defp write(owner, nil, values) do
    [[id]] = Repo.query!(@insert, [owner | values]).rows
    respond(owner, id, 201)
  end

  defp write(owner, [id | stored], values) do
    if Enum.take(values, 5) != Enum.take(stored, 5) do
      Repo.query!(@update, [id | values])
    end

    respond(owner, id, 200)
  end

  defp respond(owner, id, status) do
    [term] = Payload.places(owner, "p.id = $2", [id])
    {:ok, status, term, []}
  end

  defp stored(nil), do: %{"source" => 0}

  defp stored([_id | values]),
    do: @attributes |> Enum.zip(values) |> Map.new()

  defp lock([_, name | _] = previous, name, _now), do: Enum.at(previous, 6)
  defp lock(_previous, @placeholder, _now), do: nil
  defp lock(_previous, _name, now), do: now

  defp errors([name, lat, lon | _]) do
    for {true, message} <- [
          {blank?(name), "Name can't be blank"},
          {is_binary(name) and byte_size(name) > 255,
           "Name is too long (maximum is 255 characters)"},
          {is_nil(lat) or is_nil(lon), "Lonlat can't be blank"}
        ],
        do: message
  end

  defp inputs?(attrs) when is_map(attrs) and map_size(attrs) > 0,
    do: Enum.all?(attrs, fn {key, value} -> input?(key, value) end)

  defp inputs?(_attrs), do: false

  defp input?("tag_ids", _value), do: false
  defp input?("latitude", value), do: coordinate?(value, 90)
  defp input?("longitude", value), do: coordinate?(value, 180)
  defp input?("source", value), do: Map.has_key?(@sources, value)
  defp input?(key, value) when key in ["name", "note"], do: ascii?(value)
  defp input?(_key, _value), do: true

  defp coordinate?(nil, _limit), do: true
  defp coordinate?(value, limit) when is_integer(value), do: abs(value) <= limit

  defp coordinate?(value, limit) when is_float(value),
    do: abs(value) <= limit and Float.round(value, 6) == value

  defp coordinate?(value, limit) when is_binary(value),
    do: value =~ ~r/\A-?\d+(?:\.\d{1,6})?\z/ and abs(number(value)) <= limit

  defp coordinate?(_value, _limit), do: false

  defp ascii?(nil), do: true
  defp ascii?(value) when is_binary(value), do: value =~ ~r/\A[\x01-\x7F]*\z/
  defp ascii?(_value), do: false

  defp blank?(nil), do: true
  defp blank?(value), do: value =~ ~r/\A[\x09-\x0D ]*\z/

  defp number(nil), do: nil
  defp number(value) when is_number(value), do: value / 1
  defp number(value), do: value |> Float.parse() |> elem(0)

  defp not_found,
    do: {:ok, 404, {:object, [{"error", I18n.en!("controllers.api.record_not_found")}]}, []}
end
