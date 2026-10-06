defmodule Dawarich.MapApi.Countries do
  @moduledoc false
  alias Dawarich.{CountryNames, RailsTime, Redis, Repo}
  alias Dawarich.Tiles.Http
  alias Dawarich.Photos.ProviderCache
  defp source, do: Application.app_dir(:dawarich, "priv/country_codes.json")

  def borders do
    data = source() |> File.read!() |> Jason.decode!()
    bytes = data["borders_gzip_base64"] |> Base.decode64!() |> :zlib.gunzip()

    case Redis.cache_command(["EXISTS", "dawarich/countries_codes"]) do
      {:ok, 0} ->
        {:ok, countries} = ProviderCache.decode_json(bytes)
        ProviderCache.put("dawarich/countries_codes", countries, 86_400)

      _ ->
        :ok
    end

    {:ok, bytes}
  rescue
    _ -> {:error, 500, "Country borders request failed"}
  end

  def visited(user, params) do
    RailsTime.with_zone(user.timezone, fn ->
      with {:ok, from} <- Http.strict_timestamp(params["start_at"]),
           {:ok, to} <- Http.strict_timestamp(params["end_at"]),
           true <- from <= to do
        {where, args} = Http.point_scope(user, params, {from, to})
        aliases = source() |> File.read!() |> Jason.decode!() |> Map.get("visited_aliases", %{})

        countries =
          Repo.query!(
            "SELECT DISTINCT c.name,c.iso_a3,p.country_name,p.country FROM points p LEFT JOIN countries c ON c.id=p.country_id WHERE #{where} AND (p.anomaly=false OR p.anomaly IS NULL)",
            args
          ).rows
          |> Enum.flat_map(fn [primary, iso3, name, legacy] ->
            name = primary || present(name) || present(legacy)
            {_iso2, fallback} = if name, do: CountryNames.iso_codes(name), else: {nil, nil}
            code = present(iso3) || present(fallback)

            if name && code,
              do: [%{"iso_a3" => code, "name" => primary || Map.get(aliases, name, name)}],
              else: []
          end)
          |> Enum.uniq_by(& &1["iso_a3"])
          |> Enum.sort_by(& &1["iso_a3"])

        cutoff = Http.window(user)

        {_, plan} =
          Dawarich.Entitlements.access(
            user,
            System.get_env("SELF_HOSTED") != "false",
            DateTime.utc_now()
          )

        plan =
          if cutoff, do: [plan, DateTime.from_unix!(cutoff) |> DateTime.to_date()], else: plan

        etag =
          Http.etag([
            user.id,
            from,
            to,
            params["import_id"],
            plan,
            Http.epoch("points", user.id, {from, to})
          ])

        {:ok, %{"countries" => countries}, etag}
      else
        _ -> {:error, 422, "start_at and end_at must be valid timestamps"}
      end
    end)
  rescue
    _ -> {:error, 500, "Visited countries request failed"}
  end

  defp present(value), do: if(Http.present?(value), do: value)
end
