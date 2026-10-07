defmodule Dawarich.SharedApi.Closure do
  @moduledoc false
  alias Dawarich.Repo
  alias Dawarich.Photos.ProviderCache
  alias Dawarich.SharedApi.Photos

  def photo_ids_key(link), do: photo_ids_key(link, Photos.grant_context(link))

  def photo_ids_key(link, context) do
    zones = Enum.sort_by(context.zones, fn zone -> {zone.lat, zone.lon, zone.radius} end)
    scope = {link.user_id, link.type, link.resource_id, context.range, zones}
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(scope)) |> Base.encode16(case: :lower)
    "shared_link/#{link.id}/photo_ids/v3/#{digest}"
  end

  def allowed_photo?(link, source, id) do
    context = Photos.grant_context(link)
    not is_nil(context.range) and allowed_photo?(link, context, source, id)
  end

  defp allowed_photo?(link, context, source, id) do
    ids =
      case ProviderCache.get(photo_ids_key(link, context)) do
        {:ok, ids} when is_map(ids) -> ids
        _ -> Photos.allowed_ids(link, context)
      end

    Map.has_key?(ids, "#{source}:#{id}")
  end

  def zones(user) do
    Repo.query!(
      "SELECT p.longitude::float8,p.latitude::float8,t.privacy_radius_meters FROM tags t JOIN taggings g ON g.tag_id=t.id AND g.taggable_type='Place' JOIN places p ON p.id=g.taggable_id WHERE t.user_id=$1 AND t.privacy_radius_meters IS NOT NULL",
      [user]
    ).rows
    |> Enum.map(fn [lon, lat, radius] -> %{lon: lon || 0.0, lat: lat || 0.0, radius: radius} end)
  end

  def visible_photo?(photo, zones) do
    is_number(photo["latitude"]) and is_number(photo["longitude"]) and
      not Enum.any?(zones, fn zone ->
        distance(photo["latitude"], photo["longitude"], zone) <= zone.radius
      end)
  end

  defp distance(lat, lon, zone) do
    radians = :math.pi() / 180

    a =
      :math.pow(:math.sin((lat - zone.lat) * radians / 2), 2) +
        :math.cos(lat * radians) * :math.cos(zone.lat * radians) *
          :math.pow(:math.sin((lon - zone.lon) * radians / 2), 2)

    6_371_000 * 2 * :math.atan2(:math.sqrt(a), :math.sqrt(max(0, 1 - a)))
  end
end
