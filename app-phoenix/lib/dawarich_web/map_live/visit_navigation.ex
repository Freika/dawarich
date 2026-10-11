defmodule DawarichWeb.MapLive.VisitNavigation do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_patch: 2]
  alias Dawarich.Maps.VisitEditing
  alias DawarichWeb.MapLive.Commands

  def select(socket, id) do
    case VisitEditing.visit(socket.assigns.current_scope, id) do
      {:ok, visit} ->
        date = String.slice(visit.form["started_at"], 0, 10)

        target = %{
          "panel" => "timeline",
          "date" => date,
          "start_at" => date <> "T00:00",
          "end_at" => date <> "T23:59"
        }

        if Map.take(socket.assigns.map_url, Map.keys(target)) == target do
          {:noreply, selected(socket, visit.id)}
        else
          {:noreply,
           socket
           |> assign(:pending_visit, %{id: visit.id, target: target})
           |> push_patch(to: Commands.path(socket.assigns.map_url, target))}
        end

      _ ->
        {:noreply, clear(socket)}
    end
  end

  def params(socket, changed) do
    pending = socket.assigns[:pending_visit]
    socket = if changed, do: clear(socket), else: socket
    socket = assign(socket, :pending_visit, nil)

    if pending && Map.take(socket.assigns.map_url, Map.keys(pending.target)) == pending.target do
      {:noreply, next} = select(socket, pending.id)
      next
    else
      socket
    end
  end

  def clear(socket), do: selected(socket, nil)

  defp selected(socket, id) do
    socket |> assign(:selected_visit, id) |> push_event("visit:selection", %{id: id})
  end
end
