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
    Enum.map(photos, fn {:object, fields} ->
      photo = Map.new(fields)
      epoch = photo_epoch(photo["taken_at"], zone)

      if epoch do
        [[date]] =
          Dawarich.Repo.query!("SELECT (to_timestamp($1) AT TIME ZONE $2)::date", [epoch, zone],
            log: false
          ).rows

        photo
        |> Map.put("taken_at", DateTime.from_unix!(epoch) |> DateTime.to_iso8601())
        |> Map.put("day_key", Date.to_iso8601(date))
      else
        Map.put(photo, "day_key", nil)
      end
    end)
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
