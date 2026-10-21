defmodule DawarichWeb.MapLive.SegmentCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.LocationCommands.Segments

  def handle_event("segments:open", %{"track_id" => track_id}, socket) do
    case Segments.list(socket.assigns.current_scope, track_id) do
      {:ok, page} -> {:noreply, assign(socket, :segment_drawer, drawer(page))}
      _ -> {:noreply, assign(socket, :segment_drawer, nil)}
    end
  end

  def handle_event(
        "segment:mode",
        %{"segment_id" => id, "track_segment" => %{"transportation_mode" => mode}},
        socket
      )
      when is_binary(mode),
      do: handle_event("segment:mode", %{"segment_id" => id, "mode" => mode}, socket)

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
      %{track_id: track_id} ->
        scope = socket.assigns.current_scope

        with {:ok, _result} <- command.(scope, track_id),
             {:ok, fresh} <- Segments.list(scope, track_id) do
          {:noreply,
           socket
           |> assign(:segment_drawer, drawer(fresh))
           |> put_flash(:success, message(socket, "segment_updated"))
           |> push_event("map:invalidate", %{resource: "tracks", id: track_id})}
        else
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, message(socket, error(reason)))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp error(code) when code in [:mode_not_enabled, :reprocess_failed], do: to_string(code)
  defp error(_code), do: "reprocess_failed"

  defp message(socket, key),
    do: t(socket.assigns.locale, "controllers.tracks.segments." <> key, %{})

  defp drawer(page),
    do: %{track_id: page.track_id, segments: page.segments, modes: page.modes}
end
