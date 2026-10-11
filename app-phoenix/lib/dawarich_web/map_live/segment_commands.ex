defmodule DawarichWeb.MapLive.SegmentCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.LocationCommands.Segments

  def handle_event("segments:open", %{"track_id" => track_id}, socket) do
    case Segments.list(socket.assigns.current_scope, track_id) do
      {:ok, page} -> {:noreply, assign(socket, :segment_drawer, drawer(page, nil))}
      _ -> {:noreply, assign(socket, :segment_drawer, nil)}
    end
  end

  def handle_event("segment:mode", %{"segment_id" => id, "mode" => mode}, socket)
      when is_binary(mode),
      do: write(socket, &Segments.override(&1, &2, id, mode))

  def handle_event("segment:reset", %{"segment_id" => id}, socket),
    do: write(socket, &Segments.reset(&1, &2, id))

  def handle_event("segments:close", _params, socket),
    do: {:noreply, assign(socket, :segment_drawer, nil)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp write(socket, command) do
    case socket.assigns[:segment_drawer] do
      %{track_id: track_id} = current ->
        scope = socket.assigns.current_scope

        case command.(scope, track_id) do
          {:ok, _result} ->
            drawer =
              case Segments.list(scope, track_id) do
                {:ok, fresh} -> drawer(fresh, nil)
                {:error, reason} -> %{current | error: reason}
              end

            {:noreply,
             socket
             |> assign(:segment_drawer, Map.put(drawer, :notice, :updated))
             |> push_event("map:invalidate", %{resource: "tracks", id: track_id})}

          {:error, reason} ->
            {:noreply, assign(socket, :segment_drawer, %{current | error: reason})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp drawer(page, error),
    do: %{track_id: page.track_id, segments: page.segments, modes: page.modes, error: error}
end
