defmodule DawarichWeb.VideoStudioLiveComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.RouteVideos
  alias DawarichWeb.{NativeVideoStudio, RouteVideoUpload}

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:fixed_range_label, fn -> nil end)}
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
         put_flash(socket, :notice, message(socket, "controllers.route_videos.saved"))}

      {:error, reason} ->
        {:reply, failure(socket, reason), socket}
    end
  end

  def handle_event("video:discard", %{"signed_id" => signed}, socket) when is_binary(signed),
    do:
      {:reply, %{ok: RouteVideos.discard_upload(socket.assigns.scope, signed, []) == :ok}, socket}

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
      />
    </div>
    """
  end

  defp failure(socket, :rejected),
    do: %{ok: false, error: message(socket, "controllers.route_videos.rejected_file")}

  defp failure(socket, _reason),
    do: %{ok: false, error: message(socket, "controllers.route_videos.failed_to_save")}

  defp message(socket, key), do: t(socket.assigns.locale, key, %{})
end
