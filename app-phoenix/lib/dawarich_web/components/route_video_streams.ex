defmodule DawarichWeb.RouteVideoStreams do
  @moduledoc false
  use Phoenix.Component

  alias DawarichWeb.{Chrome, MapGalleryCards, Translate}

  def save(video, expired, locale),
    do: rendered(&saved/1, %{video: video, expired: expired, locale: locale})

  def destroy(id), do: rendered(&removed/1, %{id: id})

  def error(locale, key),
    do: rendered(&flash/1, %{locale: locale, type: "error", key: key})

  defp rendered(component, assigns),
    do:
      component.(Map.put(assigns, :__changed__, nil))
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

  defp saved(assigns) do
    ~H"""
    <turbo-stream action="prepend" target="route-video-gallery-list">
      <template>
        <MapGalleryCards.route_video_card video={@video} locale={@locale} />
      </template>
    </turbo-stream>
    <turbo-stream :for={video <- @expired} action="replace" target={"route_video_#{video.id}"}>
      <template>
        <MapGalleryCards.route_video_card video={video} locale={@locale} />
      </template>
    </turbo-stream>
    <.flash locale={@locale} type="notice" key="saved" />
    """
  end

  defp removed(assigns) do
    ~H"""
    <turbo-stream action="remove" target={"route_video_#{@id}"}></turbo-stream>
    """
  end

  defp flash(assigns) do
    assigns =
      assign(
        assigns,
        :message,
        Translate.t(assigns.locale, "controllers.route_videos." <> assigns.key, %{})
      )

    ~H"""
    <turbo-stream action="append" target="flash-messages">
      <template>
        <Chrome.flash_message type={@type} message={@message} locale={@locale} />
      </template>
    </turbo-stream>
    """
  end
end
