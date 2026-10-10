defmodule DawarichWeb.MapLive.VisitCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Maps.{Entities, VisitEditing}
  alias DawarichWeb.MapLive.Timeline

  @form ~w(name started_at ended_at)

  def handle_event("visit:new", params, socket) do
    case VisitEditing.defaults(socket.assigns.current_scope) do
      {:ok, times} ->
        form =
          Map.merge(times, %{
            "name" => "",
            "latitude" => to_string(params["latitude"]),
            "longitude" => to_string(params["longitude"])
          })

        {:noreply, assign(socket, :visit_dialog, dialog(nil, form))}

      _ ->
        {:noreply, socket}
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
    case VisitEditing.point(socket.assigns.current_scope, id) do
      {:ok, point} -> {:noreply, assign(socket, :point_address, point)}
      _ -> {:noreply, assign(socket, :point_address, nil)}
    end
  end

  def handle_event("address:close", _params, socket),
    do: {:noreply, assign(socket, :point_address, nil)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp notes(scope, id) do
    case VisitEditing.notes(scope, id) do
      {:ok, notes} -> notes
      _ -> []
    end
  end

  defp with_dialog(socket, fun) do
    case socket.assigns[:visit_dialog] do
      nil -> {:noreply, socket}
      current -> fun.(current)
    end
  end

  defp settle(socket, current, result) when result == :ok or elem(result, 0) == :ok do
    socket =
      socket
      |> assign(:visit_dialog, nil)
      |> push_event("map:invalidate", %{resource: "visits"})
      |> Timeline.reload()

    if current.id,
      do: {:noreply, socket},
      else: {:noreply, push_event(socket, "map:layer", %{layer: "visits", enabled: true})}
  end

  defp settle(socket, current, {:error, {:invalid, errors}}),
    do: {:noreply, assign(socket, :visit_dialog, %{current | errors: errors})}

  defp settle(socket, current, {:error, reason}),
    do: {:noreply, assign(socket, :visit_dialog, %{current | errors: [reason]})}

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
      note_error: nil
    }
end
