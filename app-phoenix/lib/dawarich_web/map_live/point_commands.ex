defmodule DawarichWeb.MapLive.PointCommands do
  @moduledoc false
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.LocationCommands.Points

  def handle_event("point:move", %{"point_id" => id} = params, socket) do
    attrs = Map.take(params, ~w(point track_revision history_scope))

    case Points.move(socket.assigns.current_scope, id, attrs) do
      {:ok, response} ->
        {:reply, %{ok: true, response: plain(response)}, socket}

      {:error, {:stale, response}} ->
        {:reply, %{error: "stale", response: plain(response)}, socket}

      {:error, reason} ->
        {:reply, %{error: code(reason)}, socket}
    end
  end

  def handle_event("point:delete", %{"point_id" => id}, socket) do
    case Points.delete(socket.assigns.current_scope, id) do
      :ok -> {:reply, %{ok: true}, push_event(socket, "map:invalidate", %{resource: "points"})}
      {:error, reason} -> {:reply, %{error: code(reason)}, socket}
    end
  end

  def handle_event("points:bulk_delete", %{"point_ids" => ids}, socket) when is_list(ids) do
    case Points.bulk_delete(socket.assigns.current_scope, ids) do
      {:ok, count} ->
        {:reply, %{ok: true, count: count},
         push_event(socket, "map:invalidate", %{resource: "points"})}

      {:error, reason} ->
        {:reply, %{error: code(reason)}, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp plain(term), do: term |> DawarichWeb.Api.Respond.encode() |> Jason.decode!()

  defp code({:invalid, code}), do: code
  defp code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp code(_), do: "unavailable"
end
