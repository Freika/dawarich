defmodule DawarichWeb.RouteVideoCard do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.MapGallery
  alias DawarichWeb.LocalizedTime
  @stored 0

  attr :video, :map, required: true
  attr :locale, :string, required: true

  def route_video_card(assigns) do
    file = assigns.video.files["file"]

    assigns =
      assign(assigns, file: file, playable: assigns.video.status == @stored and file != nil)

    ~H"""
    <div id={"route_video_#{@video.id}"} class="card bg-base-200 shadow-sm">
      <figure :if={@playable}>
        <video
          class="w-full rounded-t-lg"
          controls
          preload="metadata"
          playsinline
          src={MapGallery.blob_path(@file)}
        ></video>
      </figure>
      <div class="card-body p-3">
        <h4 class="card-title text-sm min-w-0 break-words">{@video.name}</h4>
        <%= unless @playable do %>
          <p class="text-xs opacity-70">
            {v(@locale, "expired_on", %{date: LocalizedTime.l(@locale, @video.shown_at, "long")})}
          </p>
          <p class="text-xs opacity-50">{v(@locale, "expired_hint")}</p>
        <% end %>
        <div class="card-actions justify-end">
          <%= if @playable do %>
            <a class="btn btn-xs btn-primary" href={MapGallery.blob_path(@file, "attachment")}>{v(
              @locale,
              "download"
            )}</a>
          <% else %>
            <button
              type="button"
              class="btn btn-xs btn-ghost"
              data-action="video-studio#restoreSettings"
              data-settings={@video.settings_json}
            >
              {v(@locale, "re_render")}
            </button>
          <% end %>
          <a
            class="btn btn-xs btn-ghost"
            data-turbo-method="delete"
            data-turbo-confirm={v(@locale, "delete_this_video")}
            href={"/route_videos/#{@video.id}"}
          >{v(@locale, "delete")}</a>
        </div>
      </div>
    </div>
    """
  end

  defp v(locale, key, bindings \\ %{}),
    do: t(locale, "route_videos.route_video." <> key, bindings)
end
