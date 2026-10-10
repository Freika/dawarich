defmodule Dawarich.Sharing.PublicSnapshot do
  @moduledoc false
  alias Dawarich.SharedApi.{Photos, Points}

  def load(%{link: link, kind: kind}, now) do
    resource = if kind in [:trip, :track], do: Dawarich.SharedLinks.ResourcePage.load(link)
    {:ok, latest} = if kind == :live, do: Points.live(link, now), else: {:ok, []}
    {:ok, points} = points(link, kind)
    photos = if kind != :missing_resource, do: Photos.gallery(link), else: []
    photos = Enum.map(photos, fn {:object, fields} -> Map.new(fields) end)

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

  defp points(link, :live), do: Points.route(link)
  defp points(_, :missing_resource), do: {:ok, []}
  defp points(%{settings: %{"show_route" => false}}, _), do: {:ok, []}
  defp points(link, _), do: Points.index(link)
end
