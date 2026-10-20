defmodule DawarichWeb.SharingNativeFrame do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{SharingNativeActive, SharingNativeForm, SharingNativeHub, SharingResource}
  embed_templates "sharing_native_frame/*"

  def frame(%{base_resource: %{type: type}} = assigns) when type in [:month, :digest] do
    DawarichWeb.SharingNativeReport.form(%{
      __changed__: nil,
      resource: assigns.base_resource,
      page: assigns.page,
      locale: assigns.locale,
      base_url: assigns[:base_url] || "",
      close: SharingResource.back(assigns.base_resource),
      errors: assigns.errors
    })
  end

  def frame(assigns) do
    assigns = assign(assigns, close: close(assigns.base_resource), title: title(assigns))
    modal(assigns)
  end

  defp close(%{type: :trip, id: id}), do: "/trips/#{id}"
  defp close(%{type: type}) when type in [:hub, :live, :timeline, :track], do: "/map/v2"
  defp close(resource), do: SharingResource.back(resource)

  defp title(%{base_resource: %{type: :hub}, locale: locale}),
    do: t(locale, "share_links.hubs.modal.share", %{})

  defp title(%{base_resource: %{type: :live}, locale: locale}),
    do: t(locale, "share_links.lives.new.share_your_live_location", %{})

  defp title(%{base_resource: %{type: :timeline}, locale: locale}),
    do: t(locale, "share_links.timelines.new.share_a_date_range", %{})

  defp title(%{base_resource: %{type: :trip}, locale: locale, page: page}),
    do: t(locale, "trips.share_links.new.share_trip", %{trip: page.trip.name})

  defp title(%{base_resource: %{type: :track}, locale: locale, page: page}),
    do: t(locale, "tracks.share_links.new.share_track", %{track: page.trip.name})

  defp title(%{locale: locale}), do: t(locale, "stats.month.share", %{})
end
