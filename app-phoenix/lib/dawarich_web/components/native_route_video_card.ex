defmodule DawarichWeb.NativeRouteVideoCard do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.MapGallery
  alias DawarichWeb.LocalizedTime
  alias Phoenix.LiveView.JS

  @stored 0

  attr :video, :map, required: true
  attr :locale, :string, required: true
  attr :target, :any, default: nil

  def native_route_video_card(assigns) do
    file = assigns.video.files["file"]

    assigns =
      assign(assigns, file: file, playable: assigns.video.status == @stored and file != nil)

    ~H"""
    <div id={"native-route-video-#{@video.id}"} class="card bg-base-200 shadow-sm">
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
        <h4 class="card-title min-w-0 text-sm [overflow-wrap:anywhere]">{@video.name}</h4>
        <%= unless @playable do %>
          <p class="text-xs opacity-70">
            {v(@locale, "expired_on", %{date: LocalizedTime.l(@locale, @video.shown_at, "long")})}
          </p>
          <p class="text-xs opacity-50">{v(@locale, "expired_hint")}</p>
        <% end %>
        <div class="card-actions flex-wrap justify-end">
          <a
            :if={@playable}
            class="btn btn-xs btn-primary h-auto"
            href={MapGallery.blob_path(@file, "attachment")}
            data-video-download
          >
            {v(@locale, "download")}
          </a>
          <button
            :if={!@playable}
            type="button"
            class="btn btn-xs btn-ghost h-auto"
            phx-click={
              JS.dispatch("dawarich:video-studio-open",
                to: "#native-video-studio",
                detail: %{recipe: @video.settings_json}
              )
            }
            data-video-restore
          >
            {v(@locale, "re_render")}
          </button>
          <button
            type="button"
            class="btn btn-xs btn-ghost h-auto"
            phx-click="video:delete"
            phx-value-id={@video.id}
            phx-target={@target}
            data-confirm={v(@locale, "delete_this_video")}
            data-video-delete
          >
            {v(@locale, "delete")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp v(locale, key, bindings \\ %{}),
    do: t(locale, "route_videos.route_video." <> key, bindings)
end
