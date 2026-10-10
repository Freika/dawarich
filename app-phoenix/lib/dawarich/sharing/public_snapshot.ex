defmodule Dawarich.Sharing.PublicSnapshot do
  @moduledoc false
  alias Dawarich.SharedApi.{Photos, Points}

  def load(%{link: link, kind: kind}, now) do
    resource = if kind in [:trip, :track], do: Dawarich.SharedLinks.ResourcePage.load(link)
    {:ok, latest} = if kind == :live, do: Points.live(link, now), else: {:ok, []}
    {:ok, points} = points(link, kind)
    photos = if kind != :missing_resource, do: Photos.gallery(link), else: []
    photos = photos(photos, if(resource, do: resource.zone, else: "UTC"))

    %{
      resource: resource,
      map: %{
        latest: latest,
        points: points,
        photos: photos,
        by_day: kind == :trip,
        meters: if(resource, do: resource.settings.meters, else: 500),
        minutes: if(resource, do: resource.settings.minutes, else: 60),
        zone: if(resource, do: resource.zone, else: "UTC")
      }
    }
  end

  def photos(photos, zone) do
    photos = Enum.map(photos, fn {:object, fields} -> Map.new(fields) end)
    epochs = Enum.map(photos, &photo_epoch(&1["taken_at"], zone))

    photos
    |> Enum.zip(epochs)
    |> Enum.map_reduce(days(Enum.reject(epochs, &is_nil/1), zone), fn
      {photo, nil}, days ->
        {Map.put(photo, "day_key", nil), days}

      {photo, epoch}, [day | days] ->
        {photo
         |> Map.put("taken_at", DateTime.from_unix!(epoch) |> DateTime.to_iso8601())
         |> Map.put("day_key", Date.to_iso8601(day)), days}
    end)
    |> elem(0)
  end

  defp days([], _zone), do: []

  defp days(epochs, zone) do
    Dawarich.Repo.query!(
      "SELECT (to_timestamp(e) AT TIME ZONE $2)::date FROM unnest($1::bigint[]) WITH ORDINALITY AS t(e, i) ORDER BY i",
      [epochs, zone],
      log: false
    ).rows
    |> List.flatten()
  end

  defp photo_epoch(raw, zone) do
    Dawarich.Imports.ImportTime.parse(raw, zone, DateTime.utc_now())
  rescue
    _ -> nil
  end

  defp points(link, :live), do: Points.route(link)
  defp points(_, :missing_resource), do: {:ok, []}
  defp points(%{settings: %{"show_route" => false}}, _), do: {:ok, []}
  defp points(link, _), do: Points.index(link)
end
