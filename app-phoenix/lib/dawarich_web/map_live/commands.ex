defmodule DawarichWeb.MapLive.Commands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3, push_patch: 2]
  import DawarichWeb.MapParts, only: [map_path: 1]

  @url ~w(start_at end_at import_id panel date place_id visit_id)
  @range ~w(start_at end_at import_id)

  def apply_params(socket, params, window) do
    url = for key <- @url, present?(params[key]), into: %{}, do: {key, params[key]}

    config = %{
      startAt: window.start,
      endAt: window.end,
      importId: url["import_id"],
      timezone: window.iana
    }

    if socket.assigns[:map_range] == config and not Map.get(socket.assigns, :map_force, false) do
      assign(socket, map_url: url)
    else
      revision = Map.get(socket.assigns, :map_revision, 0) + 1

      socket
      |> assign(map_url: url, map_range: config, map_revision: revision, map_force: false)
      |> push_event("map:config", %{revision: revision, range: config})
    end
  end

  def handle_event("map:range", %{"startAt" => first, "endAt" => last} = payload, socket)
      when is_binary(first) and is_binary(last) do
    import_id = payload["importId"]

    if present?(first) and present?(last) and (is_nil(import_id) or present?(import_id)) do
      range = %{"start_at" => first, "end_at" => last, "import_id" => import_id}
      url = merge(socket.assigns.map_url, range)

      if Map.take(url, @range) == Map.take(socket.assigns.map_url, @range) do
        {:reply, %{revision: socket.assigns.map_revision}, socket}
      else
        {:reply, %{revision: socket.assigns.map_revision + 1},
         socket |> assign(map_force: true) |> push_patch(to: map_path(url))}
      end
    else
      invalid(socket)
    end
  end

  def handle_event("map:range", _payload, socket), do: invalid(socket)

  def handle_event("map:dates", %{"start_at" => first, "end_at" => last}, socket)
      when is_binary(first) and is_binary(last),
      do: patch(socket, %{"start_at" => first, "end_at" => last})

  def handle_event("map:panel", %{"panel" => panel}, socket) when is_binary(panel),
    do: patch(socket, %{"panel" => panel})

  def handle_event(_event, _payload, socket), do: {:noreply, socket}

  def path(url, changes \\ %{}), do: map_path(merge(url, changes))

  defp patch(socket, changes),
    do: {:noreply, push_patch(socket, to: path(socket.assigns.map_url, changes))}

  defp invalid(socket), do: {:reply, %{error: "invalid_range"}, socket}

  defp merge(url, changes) do
    Enum.reduce(changes, url, fn {key, value}, acc ->
      if present?(value), do: Map.put(acc, key, to_string(value)), else: Map.delete(acc, key)
    end)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_integer(value), do: true
  defp present?(_), do: false
end
