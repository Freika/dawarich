defmodule DawarichWeb.MapLive.EntityCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Maps.Entities

  def handle_event("place:new", params, socket) do
    case DawarichWeb.MapLive.Coordinates.normalize(params) do
      {:ok, coordinates} ->
        form = Map.put(coordinates, "name", "")
        {:noreply, assign(socket, :place_dialog, dialog(nil, form, tags(socket)))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("place:edit", %{"id" => id}, socket) do
    case Entities.place(socket.assigns.current_scope, id) do
      {:ok, place} ->
        form = Map.new(place, fn {key, value} -> {key, text(value)} end)
        {:noreply, assign(socket, :place_dialog, dialog(place["id"], form, tags(socket)))}

      _ ->
        {:noreply, assign(socket, :place_dialog, nil)}
    end
  end

  def handle_event("place:change", %{"place" => attrs}, socket) when is_map(attrs) do
    case socket.assigns[:place_dialog] do
      %{form: form} = current ->
        draft =
          attrs
          |> Map.put_new("tag_ids", [])
          |> Map.take(~w(name latitude longitude note tag_ids))
          |> Map.filter(fn
            {"tag_ids", ids} -> is_list(ids) and Enum.all?(ids, &is_binary/1)
            {_, value} -> is_binary(value)
          end)
          |> then(&Map.merge(form, &1))

        {:noreply, assign(socket, :place_dialog, %{current | form: draft})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("place:save", %{"place" => attrs}, socket) when is_map(attrs) do
    case socket.assigns[:place_dialog] do
      %{id: id, form: form} = current ->
        form =
          Map.merge(
            form,
            attrs
            |> Map.put_new("tag_ids", [])
            |> Map.take(~w(name latitude longitude note tag_ids))
          )

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

  def handle_event("visit" <> _ = event, params, socket),
    do: DawarichWeb.MapLive.VisitCommands.handle_event(event, params, socket)

  def handle_event("note:" <> _ = event, params, socket),
    do: DawarichWeb.MapLive.VisitCommands.handle_event(event, params, socket)

  def handle_event("address:" <> _ = event, params, socket),
    do: DawarichWeb.MapLive.VisitCommands.handle_event(event, params, socket)

  def handle_event("place:nearby", params, socket) do
    case socket.assigns[:place_dialog] do
      nil ->
        {:noreply, socket}

      current ->
        scope = socket.assigns.current_scope
        loader = socket.assigns[:nearby_loader] || (&nearby/2)
        radius = radius(params["radius"])

        params =
          current.form
          |> Map.take(~w(latitude longitude))
          |> Map.merge(Map.take(params, ~w(latitude longitude)))
          |> then(&if(radius, do: Map.put(&1, "radius", radius), else: &1))

        {run, socket} =
          DawarichWeb.MapLive.Runs.start(
            socket,
            :place_nearby,
            current.nearby_run,
            fn -> loader.(scope, params) end,
            socket.assigns[:nearby_timeout] || 10_000
          )

        {:noreply,
         assign(socket, :place_dialog, %{
           current
           | nearby_run: run,
             nearby_radius: radius || current.nearby_radius
         })}
    end
  end

  def handle_event("place:nearby_pick", %{"index" => index}, socket) do
    with %{nearby: [_ | _] = places, form: form} = current <- socket.assigns[:place_dialog],
         {index, ""} <- Integer.parse(to_string(index)),
         %{} = place <- Enum.at(places, index) do
      picked =
        for key <- ~w(name latitude longitude),
            place[key] != nil,
            into: %{},
            do: {key, to_string(place[key])}

      {:noreply, assign(socket, :place_dialog, %{current | form: Map.merge(form, picked)})}
    else
      _ -> {:noreply, socket}
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

  def handle_async({:visit_places, _} = name, result, socket),
    do: DawarichWeb.MapLive.VisitPlaceCommands.handle_async(name, result, socket)

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp tags(socket) do
    case Entities.tags(socket.assigns.current_scope) do
      {:ok, tags} -> tags
      _ -> []
    end
  end

  defp text(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp text(value), do: to_string(value)

  defp nearby(scope, %{"radius" => radius} = params),
    do: Entities.nearby(scope, params, radius: radius)

  defp nearby(scope, params), do: Entities.nearby(scope, params)

  defp radius(value) when is_binary(value) do
    case Float.parse(value) do
      {radius, ""} when radius > 0 and radius <= 1.5 -> radius
      _ -> nil
    end
  end

  defp radius(_value), do: nil

  defp dialog(id, form, tags),
    do: %{
      id: id,
      form: form,
      errors: [],
      nearby: nil,
      nearby_radius: 0.5,
      nearby_run: nil,
      tags: tags
    }
end
