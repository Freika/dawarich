defmodule Dawarich.PlacesApi.Closure do
  @moduledoc false

  alias Dawarich.{I18n, PlaceCascade, RailsTime, Repo}
  alias Dawarich.PlacesApi.{Search, Payload}

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
    _ -> {:ok, 500, {:object, [{"error", "Internal Server Error"}]}, []}
  end

  defp dispatch(:index, owner, params, _now), do: Search.index(owner, params)

  defp dispatch(:create, owner, params, now) do
    if inputs?(params["place"]),
      do: save(owner, nil, params["place"], now),
      else:
        {:ok, 400, {:object, [{"error", "param is missing or the value is empty: place"}]}, []}
  end

  defp dispatch(action, owner, %{"id" => text} = params, now) do
    id = Dawarich.Ingest.Ruby.to_i(text)

    if id in 0..9_223_372_036_854_775_807,
      do: member(action, owner, id, params, now),
      else: not_found()
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

  defp change(:update, owner, [_, _, _, _, _, _, _, _] = row, changes, now) do
    cond do
      not inputs?(changes) ->
        {:ok, 400, {:object, [{"error", "param is missing or the value is empty: place"}]}, []}

      true ->
        save(owner, row, changes, now)
    end
  end

  defp save(owner, previous, changes, now) do
    attrs =
      Map.merge(
        stored(previous),
        Map.filter(Map.take(changes, @attributes), fn {_, value} -> scalar?(value) end)
      )

    name = if is_nil(attrs["name"]), do: nil, else: to_string(attrs["name"])

    attrs =
      Map.put(attrs, "note", if(is_nil(attrs["note"]), do: nil, else: to_string(attrs["note"])))

    values = [name, number(attrs["latitude"]), number(attrs["longitude"])]
    source = Map.get(@sources, attrs["source"], attrs["source"])
    source = if source == "", do: nil, else: source
    if source not in [nil, 0, 1, 2], do: raise(ArgumentError)
    values = values ++ [source, attrs["note"]]

    case errors(values) do
      [] ->
        result = write(owner, previous, values ++ [lock(previous, name, now), now])

        case result do
          {:ok, status, {:object, pairs}, []} ->
            id = pairs |> Map.new() |> Map.fetch!("id")
            save_tags(owner, id, changes, now, is_nil(previous))
            respond(owner, id, status)

          other ->
            other
        end

      errors ->
        {:ok, 422, {:object, [{"errors", errors}]}, []}
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
          {is_binary(name) and length(String.codepoints(name)) > 255,
           "Name is too long (maximum is 255 characters)"},
          {is_nil(lat) or is_nil(lon), "Lonlat can't be blank"}
        ],
        do: message
  end

  defp inputs?(attrs) when is_map(attrs), do: map_size(attrs) > 0
  defp inputs?(_attrs), do: false

  defp scalar?(value),
    do: is_nil(value) or is_binary(value) or is_number(value) or is_boolean(value)

  defp save_tags(owner, id, changes, now, create) do
    if Map.has_key?(changes, "tag_ids") and changes["tag_ids"] not in [nil, false] do
      ids =
        List.wrap(changes["tag_ids"])
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&Dawarich.Ingest.Ruby.to_i/1)
        |> Enum.uniq()

      ids =
        Repo.query!("SELECT id FROM tags WHERE user_id=$1 AND id=ANY($2)", [owner, ids]).rows
        |> List.flatten()

      if not create,
        do:
          Repo.query!(
            "DELETE FROM taggings WHERE taggable_type='Place' AND taggable_id=$1 AND NOT (tag_id=ANY($2))",
            [id, ids]
          )

      existing =
        Repo.query!(
          "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
          [id]
        ).rows
        |> List.flatten()

      for tag <- ids -- existing,
          do:
            Repo.query!(
              "INSERT INTO taggings (tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES ($1,'Place',$2,$3,$3)",
              [tag, id, now]
            )
    end
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(value) == ""

  defp number(nil), do: nil
  defp number(value) when is_number(value), do: value / 1
  defp number(""), do: nil
  defp number(value) when is_boolean(value), do: if(value, do: 1.0, else: 0.0)

  defp number(value),
    do: if(String.trim(value) == "", do: nil, else: Dawarich.Ingest.Ruby.to_f(value))

  defp not_found,
    do: {:ok, 404, {:object, [{"error", I18n.en!("controllers.api.record_not_found")}]}, []}
end
