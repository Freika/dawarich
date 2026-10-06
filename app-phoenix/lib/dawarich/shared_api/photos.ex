defmodule Dawarich.SharedApi.Photos do
  @moduledoc false
  alias Dawarich.{Accounts, RailsTime, Repo, UserTimeZone}
  alias Dawarich.Photos.{Index, ProviderCache, Thumbnail}
  alias Dawarich.SharedApi.{Closure, Privacy}

  def response(link, action, params \\ %{}) do
    if Dawarich.Standalone.enabled?(),
      do: native_response(link, action, params),
      else: coexistence_response(link, action)
  end

  defp coexistence_response(%{settings: %{"show_photos" => true}}, _),
    do: {:replay, "shared photo search and ACL cache remain Rails"}

  defp coexistence_response(_, :photos), do: {:ok, []}
  defp coexistence_response(_, :thumbnail), do: {:head, 404}

  defp native_response(link, action, params) do
    if link.settings["show_photos"] == true do
      case action do
        :photos -> {:ok, Enum.take(photos(link), 100) |> Enum.map(&serialize(&1, link.id))}
        :thumbnail -> thumbnail(link, params)
      end
    else
      if action == :photos, do: {:ok, []}, else: {:head, 404}
    end
  rescue
    _ -> if action == :photos, do: {:ok, []}, else: {:head, 404}
  end

  def allowed_ids(link), do: photos(link) |> ids(link)

  defp photos(link) do
    settings = Accounts.settings(link.user_id)
    user = %{id: link.user_id}
    zone = UserTimeZone.iana(Repo, settings)

    photos =
      case range(link, zone) do
        nil -> []
        {from, to} -> Index.cached(user, start_date: from, end_date: to)
      end

    zones = Closure.zones(link.user_id)
    photos = Enum.filter(photos, &Privacy.visible_photo?(&1, zones))
    ids(photos, link)
    photos
  end

  defp ids(photos, link) do
    allowed = if link.type == "trip", do: photos, else: Enum.take(photos, 100)
    ids = Map.new(allowed, &{"#{&1["source"]}:#{&1["id"]}", true})
    ProviderCache.put(Closure.photo_ids_key(link), ids, 600)
    ids
  end

  defp thumbnail(link, params) do
    source = params["source"]
    id = params["photo_id"]

    if is_binary(source) and is_binary(id) and Closure.allowed_photo?(link, source, id) do
      case Thumbnail.fetch(Accounts.settings(link.user_id), source, id, link.user_id) do
        {:ok, body} -> {:image, body}
        _ -> {:head, 404}
      end
    else
      {:head, 404}
    end
  end

  defp range(%{type: type} = link, zone) when type in ["trip", "track"] do
    {table, first, last} =
      if type == "trip",
        do: {"trips", "started_at", "ended_at"},
        else: {"tracks", "start_at", "end_at"}

    case Repo.query!("SELECT #{first},#{last} FROM #{table} WHERE id=$1 AND user_id=$2", [
           link.resource_id,
           link.user_id
         ]).rows do
      [[from, to]] -> pair(from, to, zone)
      [] -> nil
    end
  end

  defp range(%{type: "timeline", settings: settings}, zone) do
    with {:ok, from} <- Date.from_iso8601(settings["start_date"]),
         {:ok, to} <- Date.from_iso8601(settings["end_date"]) do
      [[first, last]] =
        Repo.query!(
          "SELECT $1::date::timestamp AT TIME ZONE $3 AT TIME ZONE 'UTC', ($2::date + 1)::timestamp AT TIME ZONE $3 AT TIME ZONE 'UTC' - interval '1 second'",
          [from, to, zone]
        ).rows

      pair(first, last, zone)
    else
      _ -> nil
    end
  end

  defp range(_, _zone), do: nil

  defp pair(from, to, zone) do
    with {:ok, first} <- RailsTime.iso8601(from, zone),
         {:ok, last} <- RailsTime.iso8601(to, zone),
         do: {first, last}
  end

  defp serialize(photo, link) do
    escaped = URI.encode(to_string(photo["id"]), &URI.char_unreserved?/1)

    {:object,
     [
       {"id", photo["id"]},
       {"latitude", photo["latitude"]},
       {"longitude", photo["longitude"]},
       {"source", photo["source"]},
       {"taken_at", photo["capturedAt"] || photo["localDateTime"]},
       {"thumbnail_url",
        "/api/v1/shared/#{link}/photos/#{escaped}/thumbnail?source=#{photo["source"]}"}
     ]}
  end
end
