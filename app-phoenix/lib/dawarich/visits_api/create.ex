defmodule Dawarich.VisitsApi.Create do
  @moduledoc false

  alias Dawarich.{Geocoding, I18n, Jobs, RailsEffects, RailsTime}
  alias Dawarich.VisitsApi.Effects
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.Api.Params

  @statuses %{"suggested" => 0, "confirmed" => 1, "declined" => 2}

  def call(owner, attrs, zone, now, repo \\ Jobs.repo()) do
    if is_map(attrs) do
      result =
        RailsTime.with_zone(repo, zone, fn ->
          with {:ok, from} <- time(repo, attrs["started_at"]),
               {:ok, to} <- time(repo, attrs["ended_at"]),
               :ok <- interval(from, to),
               {:ok, values} <- inputs(attrs) do
            persist(
              repo,
              owner,
              Map.merge(values, %{started_at: from, ended_at: to}),
              DateTime.to_naive(now)
            )
          end
        end)

      case result do
        {:create_unique, values} -> duplicate(repo, owner, values, zone, now)
        other -> other
      end
    else
      {:replay, "visit create root shape"}
    end
  end

  def admit(attrs) do
    case inputs(attrs) do
      {:replay, _} = replay ->
        replay

      _ ->
        if Enum.all?(~w(started_at ended_at), fn key ->
             value = attrs[key]

             Ruby.blank?(value) || (is_binary(value) && value =~ ~r/\A[a-z]{3,}\z/) ||
               match?({:ok, {:text, _}}, Params.timestamp(value))
           end),
           do: :ok,
           else: {:replay, "visit timestamp shape"}
    end
  end

  defp inputs(attrs) when is_map(attrs) do
    if Enum.all?(Map.take(attrs, ~w(name status latitude longitude started_at ended_at)), fn {_,
                                                                                              v} ->
         is_nil(v) || is_binary(v) || is_number(v)
       end) do
      with {:ok, lat} <- coordinate(attrs["latitude"]),
           {:ok, lon} <- coordinate(attrs["longitude"]),
           true <- lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180,
           {:ok, status} <- status(attrs["status"]) do
        {:ok,
         %{
           lat: lat,
           lon: lon,
           status: status,
           name: if(is_nil(attrs["name"]), do: nil, else: Ruby.to_s(attrs["name"]))
         }}
      else
        false -> error("coordinates out of range")
        other -> other
      end
    else
      {:replay, "visit create attribute shape"}
    end
  end

  defp inputs(_attrs), do: {:replay, "visit create root shape"}

  defp status(value) do
    value = if Ruby.blank?(value), do: "confirmed", else: Ruby.to_s(value)

    case Map.fetch(@statuses, value) do
      {:ok, status} -> {:ok, status}
      :error -> {:replay, "visit status shape"}
    end
  end

  defp coordinate(value) when is_number(value), do: {:ok, value * 1.0}

  defp coordinate(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> error("invalid coordinates")
    end
  end

  defp coordinate(_), do: error("invalid coordinates")

  defp time(repo, value) do
    cond do
      Ruby.blank?(value) ->
        error("invalid timestamps")

      is_binary(value) && value =~ ~r/\A[a-z]{3,}\z/ &&
          value not in ~w(September October November December January February March April May June July August) ->
        error("invalid timestamps")

      true ->
        case Params.timestamp(value) do
          {:ok, {:text, text}} ->
            [[at]] = repo.query!("SELECT $1::text::timestamptz AT TIME ZONE 'UTC'", [text]).rows
            {:ok, at}

          _ ->
            {:replay, "visit timestamp shape"}
        end
    end
  end

  defp interval(from, to),
    do:
      if(NaiveDateTime.compare(to, from) == :gt,
        do: :ok,
        else: error("ended_at must be after started_at")
      )

  defp nearby(repo, owner, values) do
    case repo.query!(
           "SELECT p.id,p.name FROM places p JOIN visits v ON v.place_id=p.id WHERE p.user_id=$1 AND v.user_id=$1 AND ST_DWithin(p.lonlat::geography,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,100) ORDER BY p.id LIMIT 1",
           [owner, values.lon, values.lat]
         ).rows do
      [row] -> row
      [] -> nil
    end
  end

  defp persist(repo, owner, values, now) do
    with {:ok, place, new?} <- place(repo, owner, values, now),
         name = if(Ruby.present?(values.name), do: values.name, else: List.last(place)),
         true <- Ruby.present?(name) do
      [place_id, _] = place

      case repo.query(
             "INSERT INTO visits (user_id,place_id,name,status,started_at,ended_at,duration,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$8) RETURNING id",
             [
               owner,
               place_id,
               name,
               values.status,
               values.started_at,
               values.ended_at,
               duration(values),
               now
             ]
           ) do
        {:ok, %{rows: [[id]]}} ->
          {:ok, visit} = Effects.load(repo, owner, id, false)
          Effects.changed(repo, nil, visit, now, true)

          if new? && values.status == 0 && Geocoding.Config.resolve(repo).enabled,
            do: RailsEffects.place_name(repo, owner, place_id)

          {:ok, Map.put(visit, :duplicate, false)}

        {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} ->
          repo.rollback({:create_unique, values})

        {:error, exception} ->
          raise exception
      end
    else
      false -> repo.rollback(error("Validation failed: Name can't be blank"))
      {:error, _, _} = error -> repo.rollback(error)
    end
  end

  defp place(repo, owner, values, now) do
    case nearby(repo, owner, values) do
      nil ->
        cond do
          Ruby.blank?(values.name) ->
            {:error, 422, I18n.en!("controllers.api.v1.visits.failed_to_create_visit")}

          length(String.to_charlist(values.name)) > 255 ->
            {:error, 422, I18n.en!("controllers.api.v1.visits.failed_to_create_visit")}

          true ->
            lock = if values.status != 0 && values.name != "Suggested place", do: now, else: nil

            [[id]] =
              repo.query!(
                "INSERT INTO places (user_id,name,latitude,longitude,lonlat,source,name_locked_at,created_at,updated_at) VALUES ($1,$2,$3::double precision,$4::double precision,ST_SetSRID(ST_MakePoint($4::double precision,$3::double precision),4326),0,$5,$6,$6) RETURNING id",
                [owner, values.name, values.lat, values.lon, lock, now]
              ).rows

            {:ok, [id, values.name], true}
        end

      place ->
        {:ok, place, false}
    end
  end

  defp duplicate(repo, owner, values, zone, now) do
    RailsTime.with_zone(repo, zone, fn ->
      case nearby(repo, owner, values) do
        [place, place_name] ->
          case repo.query!(
                 "SELECT id FROM visits WHERE user_id=$1 AND place_id=$2 AND started_at=$3",
                 [owner, place, values.started_at]
               ).rows do
            [[id]] ->
              {:ok, visit} = Effects.load(repo, owner, id, false)
              effective_name = if(Ruby.present?(values.name), do: values.name, else: place_name)

              cond do
                values.status != 0 && (visit.deleted_at != nil || visit.status == 2) ->
                  stamp = DateTime.to_naive(now)

                  repo.query!(
                    "UPDATE visits SET deleted_at=NULL,status=1,name=$2,ended_at=$3,duration=$4,updated_at=$5 WHERE id=$1",
                    [id, effective_name, values.ended_at, duration(values), stamp]
                  )

                  {:ok, revived} = Effects.load(repo, owner, id, false)
                  Effects.changed(repo, visit, revived, stamp)
                  {:ok, Map.put(revived, :duplicate, true)}

                visit.name != effective_name || visit.ended_at != values.ended_at ||
                    visit.status != values.status ->
                  {:error, 422, I18n.en!("services.visits.create.duplicate_at_place_and_time")}

                true ->
                  {:ok, Map.put(visit, :duplicate, true)}
              end

            [] ->
              error("duplicate visit")
          end

        nil ->
          error("duplicate visit")
      end
    end)
  end

  defp duration(values),
    do: div(NaiveDateTime.diff(values.ended_at, values.started_at, :second), 60)

  defp error(reason), do: {:error, 422, "Failed to create visit: " <> reason}
end
