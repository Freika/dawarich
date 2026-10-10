defmodule DawarichWeb.MapLive.EntityCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Maps.Entities

  def handle_event("place:new", params, socket) do
    form = %{
      "name" => "",
      "latitude" => to_string(params["latitude"]),
      "longitude" => to_string(params["longitude"])
    }

    {:noreply, assign(socket, :place_dialog, dialog(nil, form))}
  end

  def handle_event("place:edit", %{"id" => id}, socket) do
    case Entities.place(socket.assigns.current_scope, id) do
      {:ok, place} ->
        form = Map.new(place, fn {key, value} -> {key, to_string(value)} end)
        {:noreply, assign(socket, :place_dialog, dialog(place["id"], form))}

      _ ->
        {:noreply, assign(socket, :place_dialog, nil)}
    end
  end

  def handle_event("place:save", %{"place" => attrs}, socket) when is_map(attrs) do
    case socket.assigns[:place_dialog] do
      %{id: id, form: form} = current ->
        form = Map.merge(form, Map.take(attrs, ~w(name latitude longitude note)))

        case Entities.save_place(socket.assigns.current_scope, id, form) do
          {:ok, saved} ->
            {:noreply,
             socket
             |> assign(:place_dialog, nil)
             |> push_event("map:layer", %{layer: "places", enabled: true})
             |> push_event("map:invalidate", %{resource: "places", id: saved})}

          {:error, {:invalid, errors}} ->
            {:noreply, assign(socket, :place_dialog, %{current | form: form, errors: errors})}

          {:error, _} ->
            {:noreply, assign(socket, :place_dialog, %{current | form: form, errors: [:failed]})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("place:delete", %{"id" => id}, socket) do
    case Entities.delete_place(socket.assigns.current_scope, id) do
      :ok ->
        {:reply, %{ok: true},
         socket
         |> assign(:place_dialog, nil)
         |> push_event("map:invalidate", %{resource: "places"})}

      {:error, reason} ->
        {:reply, %{error: Atom.to_string(reason)}, socket}
    end
  end

  def handle_event("visit:status", %{"id" => id, "status" => status}, socket)
      when status in ~w(confirmed declined suggested),
      do: visit_reply(socket, Entities.visit_status(socket.assigns.current_scope, id, status))

  def handle_event("visit:delete", %{"id" => id}, socket),
    do: visit_reply(socket, Entities.delete_visit(socket.assigns.current_scope, id))

  def handle_event("place:nearby", params, socket) do
    case socket.assigns[:place_dialog] do
      nil ->
        {:noreply, socket}

      current ->
        scope = socket.assigns.current_scope
        loader = socket.assigns[:nearby_loader] || (&Entities.nearby(&1, &2))
        params = Map.take(params, ~w(latitude longitude))

        {run, socket} =
          DawarichWeb.MapLive.Runs.start(
            socket,
            :place_nearby,
            current.nearby_run,
            fn -> loader.(scope, params) end,
            socket.assigns[:nearby_timeout] || 10_000
          )

        {:noreply, assign(socket, :place_dialog, %{current | nearby_run: run})}
    end
  end

  def handle_event("place:close", _params, socket),
    do: {:noreply, assign(socket, :place_dialog, nil)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def handle_async({:place_nearby, run}, result, socket) do
    case {socket.assigns[:place_dialog], result} do
      {%{nearby_run: ^run} = current, {:ok, {:ok, places}}} ->
        {:noreply, assign(socket, :place_dialog, %{current | nearby: Enum.take(places, 10)})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp visit_reply(socket, :ok),
    do: {:reply, %{ok: true}, push_event(socket, "map:invalidate", %{resource: "visits"})}

  defp visit_reply(socket, {:error, reason}), do: {:reply, %{error: to_string(reason)}, socket}

  defp dialog(id, form), do: %{id: id, form: form, errors: [], nearby: [], nearby_run: nil}
end
