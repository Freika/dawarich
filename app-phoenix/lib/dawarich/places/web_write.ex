defmodule Dawarich.Places.WebWrite do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Places.WebTags
  @fields ~w(id name latitude longitude source note name_locked_at demo)a
  @sources %{"manual" => 0, "photon" => 1, "gpx_waypoint" => 2, "" => nil, nil => nil}
  @point "ST_SetSRID(ST_MakePoint($4::float8,$3::float8),4326)::geography"

  def run(repo, action, user, id, attrs, context) when action in [:create, :update] do
    stamp = context |> Map.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.to_naive()

    repo.transaction(fn ->
      with {:ok, previous} <- load(repo, action, user.id, id),
           {:ok, values} <- values(action, previous, attrs),
           [] <- errors(values, context[:locale] || DawarichWeb.Locale.resolve(nil, user, %{})) do
        {:ok, save(repo, user.id, previous, values, stamp)}
      else
        errors when is_list(errors) -> {:invalid, errors}
        result -> result
      end
    end)
    |> case do
      {:ok, {:ok, saved}} ->
        if action == :update, do: adopt(repo, saved, stamp)
        WebTags.save(repo, action, user.id, saved, attrs, stamp)
        {:ok, %{id: saved}}

      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load(_repo, :create, _user, _id), do: {:ok, nil}

  defp load(repo, :update, user, id) do
    case repo.query!(
           "SELECT id,name,latitude::float8,longitude::float8,source,note,name_locked_at,demo,COALESCE(ST_X(lonlat::geometry)=longitude::float8 AND ST_Y(lonlat::geometry)=latitude::float8,false) FROM places WHERE id=$1 AND user_id=$2 FOR UPDATE",
           [id, user],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [row] ->
        if List.last(row),
          do: {:ok, Map.new(Enum.zip(@fields, row))},
          else: {:replay, "legacy place geometry"}
    end
  end

  defp values(action, previous, attrs) when is_map(attrs) do
    coordinates =
      for {key, limit} <- [{"latitude", 90}, {"longitude", 180}],
          do: coordinate(Map.get(attrs, key, :omitted), limit)

    cond do
      not WebTags.supported?(attrs) ->
        {:replay, "place tags"}

      Enum.any?(
        ~w(name note),
        &(Map.has_key?(attrs, &1) and not (is_binary(attrs[&1]) or is_nil(attrs[&1])))
      ) ->
        {:replay, "place text"}

      Map.has_key?(attrs, "source") and not Map.has_key?(@sources, attrs["source"]) ->
        {:replay, "place source"}

      :unsupported in coordinates ->
        {:replay, "place coordinates"}

      action == :update and nil in coordinates ->
        {:replay, "null coordinate on update"}

      true ->
        stored =
          if previous,
            do: Map.take(previous, ~w(name latitude longitude source note)a),
            else: %{name: nil, latitude: nil, longitude: nil, source: 0, note: nil}

        changes =
          for key <- ~w(name source note),
              Map.has_key?(attrs, key),
              into: %{},
              do:
                {String.to_existing_atom(key),
                 if(key == "source", do: @sources[attrs[key]], else: attrs[key])}

        coords =
          Enum.zip(~w(latitude longitude)a, coordinates)
          |> Enum.reject(fn {_, v} -> v == :omitted end)
          |> Map.new()

        {:ok, stored |> Map.merge(changes) |> Map.merge(coords)}
    end
  end

  defp values(_action, _previous, _attrs), do: {:replay, "place parameters"}

  defp coordinate(:omitted, _limit), do: :omitted
  defp coordinate(value, _limit) when value in [nil, ""], do: nil

  defp coordinate(value, limit) when is_binary(value) do
    if value =~ ~r/\A-?\d+(?:\.\d+)?\z/ do
      {number, ""} = Float.parse(value)

      if abs(number) <= limit,
        do: value |> Decimal.new() |> Decimal.round(6) |> Decimal.to_float(),
        else: :unsupported
    else
      :unsupported
    end
  end

  defp coordinate(value, limit) when is_number(value), do: coordinate(to_string(value), limit)
  defp coordinate(_value, _limit), do: :unsupported

  defp errors(values, locale) do
    for {true, field, key, bindings} <- [
          {Ruby.blank?(values.name), "name", "errors.messages.blank", %{}},
          {is_binary(values.name) and length(String.codepoints(values.name)) > 255, "name",
           "errors.messages.too_long", %{"count" => 255}},
          {values.latitude == nil or values.longitude == nil, "lonlat", "errors.messages.blank",
           %{}}
        ],
        do: Dawarich.WebValidation.message(locale, "place", field, key, bindings)
  end

  defp save(repo, owner, previous, values, stamp) do
    lock =
      cond do
        previous && previous.name == values.name -> previous.name_locked_at
        values.name == "Suggested place" -> nil
        true -> stamp
      end

    params = [
      values.name,
      values.latitude,
      values.longitude,
      values.source,
      values.note,
      lock,
      stamp
    ]

    if previous do
      if Map.take(previous, Map.keys(values)) != values do
        repo.query!(
          "UPDATE places SET name=$2,latitude=$3::float8,longitude=$4::float8,source=$5,note=$6,name_locked_at=$7,updated_at=$8,lonlat=#{@point} WHERE id=$1",
          [previous.id | params],
          log: false
        )
      end

      previous.id
    else
      [[id]] =
        repo.query!(
          "INSERT INTO places (user_id,name,latitude,longitude,source,note,name_locked_at,created_at,updated_at,lonlat) VALUES ($1,$2,$3::float8,$4::float8,$5,$6,$7,$8,$8,#{@point}) RETURNING id",
          [owner | params],
          log: false
        ).rows

      id
    end
  end

  defp adopt(repo, id, stamp),
    do:
      repo.query!(
        "UPDATE places SET demo=false,updated_at=$2 WHERE id=$1 AND demo=true",
        [id, stamp],
        log: false
      )
end
