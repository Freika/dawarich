defmodule DawarichWeb.MapLive.TrackCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Maps.Timeline

  def handle_event("track:from_map", %{"id" => id}, socket) do
    if socket.assigns.map_url["panel"] == "timeline" do
      handle_event("track:toggle", %{"id" => id}, socket)
    else
      case Timeline.track(socket.assigns.current_scope, id) do
        {:ok, track} ->
          socket =
            assign(socket, :pending_track, %{
              id: track.id,
              range: socket.assigns.map_range,
              date: socket.assigns.map_url["date"]
            })
            |> assign(:timeline_keep_camera, true)

          DawarichWeb.MapLive.Commands.handle_event("map:panel", %{"panel" => "timeline"}, socket)

        _ ->
          {:noreply, clear(socket)}
      end
    end
  end

  def handle_event("track:toggle", %{"id" => id}, socket) do
    case Timeline.track(socket.assigns.current_scope, id) do
      {:ok, track} ->
        if socket.assigns[:track_info] && socket.assigns.track_info.id == track.id do
          {:noreply, clear(socket)}
        else
          {:noreply, socket} =
            DawarichWeb.MapLive.SegmentCommands.handle_event(
              "segments:open",
              %{"track_id" => track.id},
              socket
            )

          {:noreply,
           socket
           |> assign(:track_info, Map.put(track, :points, false))
           |> push_event("track:selection", %{id: track.id, points: false})}
        end

      _ ->
        {:noreply, clear(socket)}
    end
  end

  def handle_event("track:points", _, socket) do
    case socket.assigns[:track_info] do
      %{id: id, points: points} = info ->
        case Timeline.track(socket.assigns.current_scope, id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:track_info, %{info | points: not points})
             |> push_event("track:selection", %{id: id, points: not points})}

          _ ->
            {:noreply, clear(socket)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("track:close", _, socket), do: {:noreply, clear(socket)}
  def handle_event(_, _, socket), do: {:noreply, socket}

  def resume(socket) do
    pending = socket.assigns[:pending_track]
    socket = assign(socket, :pending_track, nil)

    if pending && socket.assigns.map_url["panel"] == "timeline" &&
         pending.range == socket.assigns.map_range &&
         pending.date == socket.assigns.map_url["date"] do
      {:noreply, socket} = handle_event("track:toggle", %{"id" => pending.id}, socket)
      socket
    else
      socket
    end
  end

  def clear(socket) do
    socket
    |> assign(:track_info, nil)
    |> assign(:segment_drawer, nil)
    |> push_event("track:selection", %{id: nil, points: false})
  end
end
