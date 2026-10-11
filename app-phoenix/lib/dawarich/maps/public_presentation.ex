defmodule Dawarich.Maps.PublicPresentation do
  @moduledoc false

  def project(%{resource: nil} = page, _family?), do: Map.take(page, [:link, :resource])

  def project(%{kind: kind} = page, _family?) when kind == :live or is_tuple(kind),
    do: %{link: page.link, resource: nil}

  def project(%{link: link, resource: resource}, family?) do
    photos = Dawarich.Sharing.PublicSnapshot.photos(resource.photos, resource[:zone] || "UTC")
    grouped = Enum.group_by(photos, & &1["day_key"])

    days =
      Enum.map(resource.days, fn day ->
        day
        |> Map.put(:note, if(day.note, do: %{body: day.note}))
        |> Map.put(:photos, Map.get(grouped, Date.to_iso8601(day.date), []))
      end)

    resource =
      resource
      |> Map.put(:days, days)
      |> Map.put(:family, family?)
      |> Map.put(:started, resource[:started_at])
      |> Map.put(:ended, resource[:ended_at])
      |> Map.put(:started_at, %{local: resource[:started_at]})
      |> Map.put(:ended_at, %{local: resource[:ended_at]})
      |> Map.put(:settings, %{
        unit: resource[:unit],
        factor: Dawarich.Distance.convert(1, resource[:unit] || "km")
      })
      |> Map.put(:flags, Dawarich.CountryNames.table())

    %{link: link, resource: resource}
  end
end
