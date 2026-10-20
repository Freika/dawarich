defmodule DawarichWeb.MapLive.VisitCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Maps.{Entities, VisitEditing}
  alias DawarichWeb.MapLive.Timeline

  @form ~w(name started_at ended_at)

  def handle_event("visit:new", params, socket) when is_map(params) do
    times = [from: params["started_at"], to: params["ended_at"]]

    with {:ok, coordinates} <- DawarichWeb.MapLive.Coordinates.normalize(params),
         {:ok, times} <- VisitEditing.defaults(socket.assigns.current_scope, times) do
      form =
        Map.merge(times, %{
          "name" =>
            if(is_binary(params["name"]), do: String.slice(params["name"], 0, 255), else: ""),
          "latitude" => coordinates["latitude"],
          "longitude" => coordinates["longitude"]
        })

      {:noreply, assign(socket, :visit_dialog, dialog(nil, form))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("visit:inline", %{"id" => id}, socket) do
    case socket.assigns[:visit_dialog] do
      %{inline: true, id: current} when current != nil ->
        if to_string(current) == to_string(id),
          do: {:noreply, assign(socket, :visit_dialog, nil)},
          else: inline(socket, id)

      _ ->
        inline(socket, id)
    end
  end

  def handle_event("visit:edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case VisitEditing.visit(scope, id) do
      {:ok, visit} ->
        {:noreply,
         assign(socket, :visit_dialog, %{
           dialog(visit.id, visit.form)
           | places: visit.places,
             place_id: visit.place_id,
             notes: notes(scope, visit.id)
         })}

      _ ->
        {:noreply, assign(socket, :visit_dialog, nil)}
    end
  end

  def handle_event("visit:save", %{"name" => _} = params, socket),
    do: handle_event("visit:save", %{"visit" => Map.take(params, @form)}, socket)

  def handle_event("visit:save", %{"visit" => attrs}, socket) when is_map(attrs) do
    with_dialog(socket, fn current ->
      form = Map.merge(current.form, Map.take(attrs, @form))
      scope = socket.assigns.current_scope

      result =
        if current.id,
          do: VisitEditing.update(scope, current.id, Map.take(form, @form)),
          else: VisitEditing.create(scope, form)

      settle(socket, %{current | form: form}, result)
    end)
  end

  def handle_event("visit:place", %{"place_id" => place_id}, socket) when is_binary(place_id) do
    with_dialog(socket, fn
      %{id: nil} ->
        {:noreply, socket}

      current ->
        result =
          VisitEditing.update(socket.assigns.current_scope, current.id, %{"place_id" => place_id})

        settle(socket, current, result)
    end)
  end

  def handle_event("visit:close", _params, socket),
    do: {:noreply, assign(socket, :visit_dialog, nil)}

  def handle_event("visit:status", %{"id" => id, "status" => status}, socket)
      when status in ~w(confirmed declined suggested),
      do: reply(socket, Entities.visit_status(socket.assigns.current_scope, id, status))

  def handle_event("visit:delete", %{"id" => id}, socket),
    do: reply(socket, Entities.delete_visit(socket.assigns.current_scope, id))

  def handle_event("visits:merge", %{"ids" => ids}, socket) when is_list(ids),
    do: reply(socket, VisitEditing.merge(socket.assigns.current_scope, ids))

  def handle_event("note:add", %{"note" => %{"body" => body}}, socket) when is_binary(body) do
    with_dialog(socket, fn
      %{id: nil} ->
        {:noreply, socket}

      current ->
        scope = socket.assigns.current_scope

        case VisitEditing.add_note(scope, current.id, body) do
          :ok ->
            notes = notes(scope, current.id)
            {:noreply, assign(socket, :visit_dialog, %{current | notes: notes, note_error: nil})}

          {:error, reason} ->
            {:noreply, assign(socket, :visit_dialog, %{current | note_error: reason})}
        end
    end)
  end

  def handle_event("address:open", %{"id" => id}, socket) do
    text =
      case VisitEditing.point(socket.assigns.current_scope, id) do
        {:ok, point} -> DawarichWeb.PointListFormat.address(point, false)
        _ -> nil
      end

    {:reply, %{text: text}, socket}
  end

  def handle_event("visit:place_" <> _ = event, params, socket),
    do: DawarichWeb.MapLive.VisitPlaceCommands.handle_event(event, params, socket)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp notes(scope, id) do
    case VisitEditing.notes(scope, id) do
      {:ok, notes} -> notes
      _ -> []
    end
  end

  defp inline(socket, id) do
    {:noreply, socket} = handle_event("visit:edit", %{"id" => id}, socket)

    dialog = socket.assigns.visit_dialog
    {:noreply, assign(socket, :visit_dialog, dialog && Map.put(dialog, :inline, true))}
  end

  defp with_dialog(socket, fun) do
    case socket.assigns[:visit_dialog] do
      nil -> {:noreply, socket}
      current -> fun.(current)
    end
  end

  def settle(socket, current, result) when result == :ok or elem(result, 0) == :ok do
    socket =
      socket
      |> assign(:visit_dialog, nil)
      |> push_event("map:invalidate", %{resource: "visits"})
      |> Timeline.reload()

    if current.id,
      do: {:noreply, socket},
      else:
        {:noreply,
         socket |> enable_layer() |> push_event("map:layer", %{layer: "visits", enabled: true})}
  end

  def settle(socket, current, {:error, {:invalid, errors}}),
    do: {:noreply, assign(socket, :visit_dialog, %{current | errors: errors})}

  def settle(socket, current, {:error, reason}),
    do: {:noreply, assign(socket, :visit_dialog, %{current | errors: [reason]})}

  defp enable_layer(%{assigns: %{map_settings: %{saved: settings}, map_config: _}} = socket) do
    layers = Enum.uniq((settings["enabled_map_layers"] || []) ++ ["Visits"])

    {:noreply, socket} =
      DawarichWeb.MapLive.Native.handle_event(
        "settings:map_layers",
        %{"layers" => layers},
        socket
      )

    socket
  end

  defp enable_layer(socket), do: socket

  defp reply(socket, result) when result == :ok or elem(result, 0) == :ok,
    do:
      {:reply, %{ok: true},
       socket |> push_event("map:invalidate", %{resource: "visits"}) |> Timeline.reload()}

  defp reply(socket, {:error, reason}), do: {:reply, %{error: to_string(reason)}, socket}

  defp dialog(id, form),
    do: %{
      id: id,
      form: form,
      errors: [],
      places: [],
      place_id: nil,
      notes: [],
      note_error: nil,
      search: nil
    }
end
