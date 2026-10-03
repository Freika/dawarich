defmodule Dawarich.NotesApi.Write do
  @moduledoc false

  alias Dawarich.{I18n, RailsTime, Repo}
  alias Dawarich.NotesApi.{Payload, Validation}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @keys ~w(title body attachable_type attachable_id noted_at lonlat)
  @input ~w(title body latitude longitude attachable_type attachable_id noted_at)
  @stored "SELECT title, body, attachable_type, attachable_id, noted_at, encode(ST_AsEWKB(lonlat::geometry),'hex') FROM notes WHERE user_id = $1 AND id = $2"
  @point "ST_GeomFromEWKB(decode($7::text,'hex'))::geography"

  def create(owner, attrs, zone, now), do: run(owner, nil, attrs, zone, now)
  def update(owner, id, attrs, zone, now), do: run(owner, id, attrs, zone, now)

  def destroy(owner, id, zone) do
    RailsTime.with_zone(zone, fn ->
      case Repo.query!("DELETE FROM notes WHERE user_id = $1 AND id = $2 RETURNING id", [
             owner,
             id
           ]).rows do
        [[_]] ->
          {:ok, 200,
           {:object,
            [{"message", I18n.en!("controllers.api.v1.notes.note_was_successfully_deleted")}]}}

        [] ->
          :not_found
      end
    end)
  end

  defp run(owner, id, attrs, zone, now) do
    if inputs?(attrs) do
      RailsTime.with_zone(zone, fn ->
        with {:ok, old} <- stored(owner, id),
             {:ok, changes} <- coerce(Map.take(attrs, @input)),
             values = Map.merge(old, changes),
             {:ok, errors} <-
               Validation.errors(Map.merge(values, %{"id" => id, "user_id" => owner})) do
          if errors == [],
            do: persist(owner, id, old, values, DateTime.to_naive(now)),
            else: {:ok, 422, {:object, [{"errors", errors}]}}
        end
      end)
    else
      {:replay, "note attribute shape"}
    end
  end

  defp stored(_owner, nil), do: {:ok, Map.new(@keys, &{&1, nil})}

  defp stored(owner, id) do
    case Repo.query!(@stored, [owner, id]).rows do
      [row] -> {:ok, Map.new(Enum.zip(@keys, row))}
      [] -> :not_found
    end
  end

  defp inputs?(attrs) when is_map(attrs) and map_size(attrs) > 0,
    do:
      Enum.all?(Map.take(attrs, @input), fn {_, value} ->
        is_nil(value) or is_binary(value) or is_number(value)
      end)

  defp inputs?(_attrs), do: false

  defp coerce(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case value(key, value) do
        {:ok, converted} -> {:cont, {:ok, Map.put(acc, key, converted)}}
        replay -> {:halt, replay}
      end
    end)
    |> geometry()
  end

  defp value("noted_at", value), do: timestamp(value)
  defp value("attachable_id", value) when is_integer(value) or is_nil(value), do: {:ok, value}

  defp value("attachable_id", value) when is_binary(value),
    do: {:ok, if(Ruby.blank?(value), do: nil, else: Dawarich.RubyInteger.to_i(value))}

  defp value("attachable_id", _value), do: {:replay, "note attachable id"}
  defp value(key, value) when key in ["latitude", "longitude"], do: {:ok, value}
  defp value(_key, nil), do: {:ok, nil}
  defp value(_key, value), do: {:ok, Ruby.to_s(value)}

  defp timestamp(nil), do: {:ok, nil}

  defp timestamp(value) when is_binary(value) do
    if Ruby.blank?(value) do
      {:ok, nil}
    else
      case DateTime.from_iso8601(value) do
        {:ok, at, _} -> {:ok, DateTime.to_naive(at)}
        _ -> {:replay, "note timestamp shape"}
      end
    end
  end

  defp timestamp(_value), do: {:replay, "note timestamp shape"}

  defp geometry({:ok, attrs}) do
    lat = attrs["latitude"]
    lon = attrs["longitude"]

    if Ruby.present?(lat) and Ruby.present?(lon) do
      [[hex]] =
        Repo.query!(
          "SELECT encode(ST_AsEWKB(ST_SetSRID(ST_MakePoint($1,$2),4326)::geography::geometry),'hex')",
          [number(lon), number(lat)]
        ).rows

      {:ok, attrs |> Map.drop(~w(latitude longitude)) |> Map.put("lonlat", hex)}
    else
      {:ok, Map.drop(attrs, ~w(latitude longitude))}
    end
  end

  defp geometry(replay), do: replay
  defp number(value) when is_number(value), do: value * 1.0
  defp number(value), do: Ruby.to_f(value)

  defp persist(owner, nil, _old, values, now) do
    args = args(owner, values) ++ [now]

    [[id]] =
      Repo.query!(
        "INSERT INTO notes (user_id,title,body,attachable_type,attachable_id,noted_at,lonlat,created_at,updated_at) " <>
          "VALUES ($1,$2,$3,$4,$5,$6,#{@point},$8,$8) RETURNING id",
        args
      ).rows

    respond(owner, id, 201)
  end

  defp persist(owner, id, old, values, now) do
    if old != values do
      Repo.query!(
        "UPDATE notes SET title=$2,body=$3,attachable_type=$4,attachable_id=$5,noted_at=$6,lonlat=#{@point},updated_at=$8 " <>
          "WHERE user_id=$1 AND id=$9",
        args(owner, values) ++ [now, id]
      )
    end

    respond(owner, id, 200)
  end

  defp args(owner, values), do: [owner | Enum.map(@keys, &values[&1])]

  defp respond(owner, id, status) do
    [row] = Payload.rows("n.user_id=$1 AND n.id=$2", [owner, id])
    {:ok, status, Payload.term(row)}
  end
end
