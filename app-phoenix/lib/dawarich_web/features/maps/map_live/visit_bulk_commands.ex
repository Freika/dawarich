defmodule DawarichWeb.MapLive.VisitBulkCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Maps.VisitEditing
  alias DawarichWeb.MapLive.Timeline

  def handle_event("timeline:select_day", %{"date" => date}, socket) when is_binary(date),
    do: {:noreply, assign(socket, :timeline_selection, %{day: date, ids: []})}

  def handle_event("timeline:select", %{"id" => id}, socket) when is_binary(id) do
    case socket.assigns[:timeline_selection] do
      %{ids: ids} = selection ->
        ids = if id in ids, do: List.delete(ids, id), else: ids ++ [id]
        {:noreply, assign(socket, :timeline_selection, %{selection | ids: ids})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("timeline:select_cancel", _params, socket),
    do: {:noreply, assign(socket, :timeline_selection, nil)}

  def handle_event("visits:bulk", %{"action" => action, "ids" => ids}, socket)
      when is_binary(action) and is_list(ids) do
    case VisitEditing.bulk(socket.assigns.current_scope, action, ids) do
      :ok ->
        {:reply, %{ok: true},
         socket
         |> assign(:timeline_selection, nil)
         |> push_event("map:invalidate", %{resource: "visits"})
         |> Timeline.reload()}

      {:error, reason} ->
        {:reply, %{error: to_string(reason)}, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}
end
