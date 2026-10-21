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
           |> assign(:timeline_keep_camera, true)
           |> push_patch(to: Commands.path(socket.assigns.map_url, target))}
        end

      _ ->
        {:noreply,
         socket
         |> clear()
         |> DawarichWeb.MapLive.Toast.push(:error, "messages.failed_to_load_visit_details")}
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

  def hydrate(socket) do
    url = socket.assigns.map_url
    timeline = socket.assigns[:timeline]

    if url["panel"] == "timeline" && timeline && timeline.status == :ready &&
         !socket.assigns[:selected_visit] && is_binary(url["visit_id"]) do
      date =
        case Date.from_iso8601(url["date"] || "") do
          {:ok, date} -> Date.to_iso8601(date)
          _ -> Date.to_iso8601(socket.assigns.page.window.start_date)
        end

      entry =
        Enum.find_value(timeline.feed.days, fn day ->
          if day.date == date,
            do:
              Enum.find(
                day.entries,
                &(&1.type == "visit" && to_string(&1.visit_id) == url["visit_id"])
              )
        end)

      with %{visit_id: id} <- entry,
           {:ok, %{id: ^id}} <- VisitEditing.visit(socket.assigns.current_scope, id) do
        selected(socket, id)
      else
        _ -> socket
      end
    else
      socket
    end
  end

  def clear(socket), do: selected(socket, nil)

  defp selected(socket, id) do
    socket |> assign(:selected_visit, id) |> push_event("visit:selection", %{id: id})
  end
end
