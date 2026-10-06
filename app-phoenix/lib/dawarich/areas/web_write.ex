defmodule Dawarich.Areas.WebWrite do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @fields ~w(name latitude longitude radius)

  def create(repo, user, attrs, ctx), do: write(repo, user, nil, attrs, ctx)
  def update(repo, user, id, attrs, ctx), do: write(repo, user, id, attrs, ctx)

  defp write(repo, user, id, attrs, ctx) do
    case repo.transaction(fn ->
           before = load!(repo, user.id, id)
           values = Map.merge(before || %{}, Map.take(attrs, @fields))
           errors = validate(values)
           if errors != [], do: repo.rollback({:invalid, errors})
           area = save!(repo, user.id, id, values, before, ctx.now)
           relabel!(repo, area.id, values, before, ctx.now)
           %{area: area}
         end) do
      {:ok, result} -> {:ok, result}
      {:error, result} -> result
    end
  end

  defp relabel!(repo, id, values, before, now) do
    needed =
      is_nil(before) or
        Enum.any?(~w(latitude longitude radius), &(number(values[&1]) != number(before[&1])))

    if needed do
      if Dawarich.Jobs.Ownership.lock(repo, "command:areas.relabel_visits") != :oban,
        do: repo.rollback(:rails)

      repo.query!(
        "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,'areas.relabel_visits',1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING",
        [
          Ecto.UUID.bingenerate(),
          %{"area_id" => id},
          %{"producer" => "Phoenix Area"},
          id,
          to_string(id),
          now
        ]
      )
    end
  end

  defp load!(_repo, _user, nil), do: nil

  defp load!(repo, user, id) do
    case repo.query!(
           "SELECT name,latitude::text,longitude::text,radius::text FROM areas WHERE id=$1 AND user_id=$2 FOR UPDATE",
           [id, user]
         ).rows do
      [row] -> Map.new(Enum.zip(@fields, row))
      [] -> repo.rollback(:not_found)
    end
  end

  defp validate(values) do
    presence =
      for key <- @fields, Ruby.blank?(values[key]), do: "#{String.capitalize(key)} can't be blank"

    presence ++
      numeric(values["radius"], "Radius", 0, nil, true) ++
      numeric(values["latitude"], "Latitude", -90, 90, false) ++
      numeric(values["longitude"], "Longitude", -180, 180, false)
  end

  defp numeric(value, name, low, high, exclusive) do
    case number(value) do
      nil -> ["#{name} is not a number"]
      n when exclusive and n <= low -> ["#{name} must be greater than #{low}"]
      n when n < low -> ["#{name} must be greater than or equal to #{low}"]
      n when not is_nil(high) and n > high -> ["#{name} must be less than or equal to #{high}"]
      _ -> []
    end
  end

  defp number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp number(_), do: nil

  defp save!(repo, user, nil, values, _before, now) do
    [[id]] =
      repo.query!(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,$2,$3::text::numeric,$4::text::numeric,$5,$6,$6) RETURNING id",
        [
          user,
          values["name"],
          values["latitude"],
          values["longitude"],
          trunc(number(values["radius"])),
          DateTime.to_naive(now)
        ]
      ).rows

    %{id: id}
  end

  defp save!(repo, user, id, values, before, now) do
    changed =
      values["name"] != before["name"] or
        Enum.any?(~w(latitude longitude radius), &(number(values[&1]) != number(before[&1])))

    if changed do
      repo.query!(
        "UPDATE areas SET name=$3,latitude=$4::text::numeric,longitude=$5::text::numeric,radius=$6,updated_at=$7 WHERE id=$1 AND user_id=$2",
        [
          id,
          user,
          values["name"],
          values["latitude"],
          values["longitude"],
          trunc(number(values["radius"])),
          DateTime.to_naive(now)
        ]
      )
    end

    %{id: id}
  end
end
