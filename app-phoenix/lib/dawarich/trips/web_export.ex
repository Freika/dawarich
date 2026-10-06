defmodule Dawarich.Trips.WebExport do
  @moduledoc false
  alias Dawarich.{RailsTime, TimeZoneName, UserTimeZone}
  @formats %{"json" => 0, "gpx" => 1}

  def prepare(repo, user, id, format, _context) do
    case repo.query!(
           "SELECT name, started_at, ended_at FROM trips WHERE id = $1 AND user_id = $2",
           [id, user.id],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [[name, first, last]] ->
        cond do
          not is_map_key(@formats, format) ->
            {:invalid, :format}

          not is_binary(name) and not is_nil(name) ->
            {:replay, "trip export name shape"}

          not is_map(user.settings) ->
            {:replay, "trip export settings"}

          true ->
            export(repo, user, id, name || "", first, last, format)
        end
    end
  end

  defp export(repo, user, id, name, first, last, format) do
    zone = UserTimeZone.zone(user.settings)
    zone = if zone in [nil, ""], do: "UTC", else: zone

    RailsTime.with_zone(repo, zone, fn ->
      [[date]] =
        repo.query!(
          "SELECT (($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE $2)::date",
          [first, TimeZoneName.to_iana(zone)],
          log: false
        ).rows

      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      slug =
        Dawarich.Achievements.UiText.search(name, locale)
        |> String.replace(~r/[^a-z0-9_-]+/i, "-")
        |> String.replace(~r/-+/, "-")
        |> String.trim("-")
        |> String.downcase()

      slug = if slug == "", do: Integer.to_string(id), else: slug

      {:ok,
       %{
         name: "trip_#{slug}_#{date}.#{format}",
         file_format: @formats[format],
         start_at: first,
         end_at: last
       }}
    end)
  end
end
