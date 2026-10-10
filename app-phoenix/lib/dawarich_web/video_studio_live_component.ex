defmodule DawarichWeb.VideoStudioLiveComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.NativeRouteVideoCard, only: [native_route_video_card: 1]

  alias Dawarich.RouteVideos
  alias DawarichWeb.{Icon, NativeVideoStudio, RouteVideoUpload}
  alias Phoenix.LiveView.JS

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:fixed_range_label, fn -> nil end)
     |> then(fn socket -> assign_new(socket, :videos, fn -> gallery(socket) end) end)}
  end

  def handle_event("video:upload_target", params, socket) do
    attrs = %{
      "filename" => params["filename"],
      "byte_size" => params["byte_size"],
      "checksum" => params["checksum"],
      "content_type" => Map.get(params, "content_type", "video/mp4")
    }

    case RouteVideoUpload.target(socket.assigns.scope, attrs, socket.assigns.base_url) do
      {:ok, target} -> {:reply, Map.put(target, :ok, true), socket}
      {:error, reason} -> {:reply, failure(socket, reason), socket}
    end
  end

  def handle_event("video:save", %{"signed_id" => signed} = params, socket)
      when is_binary(signed) do
    attrs = %{"signed_id" => signed, "name" => params["name"], "settings" => params["settings"]}

    case RouteVideos.create_video(socket.assigns.scope, attrs, []) do
      {:ok, %{id: id, evicted: evicted}} ->
        send(self(), {__MODULE__, {:saved, id, evicted}})

        {:reply, %{ok: true, id: id},
         socket
         |> assign(:videos, gallery(socket))
         |> put_flash(:notice, message(socket, "controllers.route_videos.saved"))}

      {:error, reason} ->
        {:reply, failure(socket, reason), socket}
    end
  end

  def handle_event("video:discard", %{"signed_id" => signed}, socket) when is_binary(signed),
    do:
      {:reply, %{ok: RouteVideos.discard_upload(socket.assigns.scope, signed, []) == :ok}, socket}

  def handle_event("video:delete", %{"id" => id}, socket) do
    socket =
      case RouteVideos.destroy_video(socket.assigns.scope, id, []) do
        {:ok, _id} ->
          put_flash(socket, :notice, message(socket, "controllers.route_videos.deleted"))

        {:error, :not_found} ->
          socket

        {:error, _} ->
          put_flash(socket, :error, message(socket, "controllers.route_videos.failed_to_save"))
      end

    {:noreply, assign(socket, :videos, gallery(socket))}
  end

  def handle_event(_event, _params, socket),
    do: {:reply, failure(socket, :invalid_upload), socket}

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <NativeVideoStudio.video_studio
        themes={@themes}
        locale={@locale}
        fixed_range_label={@fixed_range_label}
        target={@myself}
      >
        <:gallery>
          <details
            id="native-video-gallery"
            class="collapse collapse-arrow rounded-lg border border-base-content/10 bg-base-100"
            phx-mounted={JS.ignore_attributes("open")}
          >
            <summary class="collapse-title min-h-0 cursor-pointer font-medium">
              <span class="flex items-center gap-2">
                <Icon.icon name="camera" class="h-4 w-4 shrink-0 opacity-70" />
                {studio(@locale, "recent_videos")}
              </span>
            </summary>
            <div class="collapse-content space-y-3">
              <p class="text-xs opacity-60">
                {studio(@locale, "videos_from_save_to_gallery_they_stay_here")}
              </p>
              <div id="native-video-gallery-list" class="space-y-3">
                <.native_route_video_card
                  :for={video <- @videos}
                  video={video}
                  locale={@locale}
                  target={@myself}
                />
              </div>
            </div>
          </details>
        </:gallery>
      </NativeVideoStudio.video_studio>
    </div>
    """
  end

  defp failure(socket, :rejected),
    do: %{ok: false, error: message(socket, "controllers.route_videos.rejected_file")}

  defp failure(socket, _reason),
    do: %{ok: false, error: message(socket, "controllers.route_videos.failed_to_save")}

  defp message(socket, key), do: t(socket.assigns.locale, key, %{})

  defp studio(locale, key), do: t(locale, "route_videos.studio." <> key, %{})

  defp gallery(socket) do
    case RouteVideos.gallery(socket.assigns.scope, []) do
      {:ok, videos} -> videos
      {:error, _} -> []
    end
  end
end
