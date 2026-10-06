defmodule Dawarich.Trips.Photos do
  @moduledoc false
  alias Dawarich.Photos.Index
  alias Dawarich.Imports.ImportTime
  alias Dawarich.{Repo, TimeZoneName}

  def load(user, first, last, zone) do
    params = %{"start_date" => iso(first), "end_date" => iso(last)}

    photos =
      case Index.fetch(user, params, settings: user.settings) do
        {:ok, assets, _errors} -> Enum.map(assets, &thumbnail(&1, user))
        _ -> []
      end

    sources = photos |> Enum.map(& &1.source) |> Enum.uniq()

    %{
      photos: photos,
      days: group(photos, zone),
      sources: sources,
      previews: dominant(photos) |> Enum.take_random(12),
      links: Map.new(sources, &{&1, search_url(&1, user.settings, first, last)})
    }
  end

  def group(photos, zone) do
    Enum.reduce(photos, %{}, fn photo, days ->
      case date(photo.taken_at, zone) do
        nil -> days
        day -> Map.update(days, day, [photo], &(&1 ++ [photo]))
      end
    end)
  end

  defp date(raw, zone) do
    if time = ImportTime.parse(raw, zone, DateTime.utc_now()) do
      [[day]] =
        Repo.query!(
          "SELECT (to_timestamp($1) AT TIME ZONE $2)::date",
          [time, TimeZoneName.to_iana(zone)],
          log: false
        ).rows

      day
    end
  rescue
    _ -> nil
  end

  defp thumbnail(asset, user) do
    %{
      id: asset["id"],
      url:
        "/api/v1/photos/#{asset["id"]}/thumbnail.jpg?api_key=#{user.api_key}&source=#{asset["source"]}",
      source: asset["source"],
      orientation: asset["orientation"],
      taken_at: asset["capturedAt"] || asset["localDateTime"]
    }
  end

  defp dominant(photos) do
    vertical = Enum.filter(photos, &(&1.orientation == "portrait"))
    horizontal = Enum.filter(photos, &(&1.orientation == "landscape"))
    if length(vertical) > length(horizontal), do: vertical, else: horizontal
  end

  defp search_url("immich", settings, first, last) do
    query =
      Jason.encode!(%{
        "takenAfter" => "#{NaiveDateTime.to_date(first)}T00:00:00.000Z",
        "takenBefore" => "#{NaiveDateTime.to_date(last)}T23:59:59.999Z"
      })

    settings["immich_url"] <> "/search?query=" <> URI.encode_www_form(query)
  end

  defp search_url("photoprism", settings, first, _last),
    do:
      settings["photoprism_url"] <>
        "/library/browse?view=cards&year=#{first.year}&month=#{first.month}&order=newest&public=true&quality=3"

  defp iso(time),
    do:
      time
      |> NaiveDateTime.truncate(:second)
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_iso8601()
end
