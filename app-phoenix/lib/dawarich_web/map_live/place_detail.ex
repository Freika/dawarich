defmodule DawarichWeb.MapLive.PlaceDetail do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2, push_event: 3, put_flash: 3]
  alias Dawarich.Places
  alias DawarichWeb.MapLive.Commands

  def hydrate(socket) do
    case socket.assigns.map_url["place_id"] do
      nil -> assign(socket, :place_detail, nil)
      id -> load(socket, id)
    end
  end

  def refresh(socket) do
    case socket.assigns[:place_detail] do
      %{id: id} -> load(socket, id)
      _ -> socket
    end
  end

  def handle_event("place:detail:open", %{"id" => id}, socket) do
    socket = load(socket, id)

    case socket.assigns.place_detail do
      %{id: id} ->
        {:noreply,
         push_patch(socket, to: Commands.path(socket.assigns.map_url, %{"place_id" => id}))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("place:detail:close", _, socket), do: {:noreply, close(socket)}

  def handle_event("place:detail:save", %{"place" => attrs}, socket) when is_map(attrs) do
    case socket.assigns[:place_detail] do
      %{id: id} ->
        case Places.update(socket.assigns.current_scope, id, Map.take(attrs, ["note"])) do
          {:ok, _} ->
            {:noreply, socket |> load(id) |> notice("controllers.places.updated")}

          {:error, :not_found} ->
            {:noreply, close(socket)}

          _ ->
            {:noreply,
             put_flash(
               socket,
               :error,
               DawarichWeb.Translate.t(
                 socket.assigns.locale,
                 "controllers.api.v1.settings.something_went_wrong",
                 %{}
               )
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("place:detail:delete", _, socket) do
    case socket.assigns[:place_detail] do
      %{id: id} ->
        case Places.delete(socket.assigns.current_scope, id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:place_dialog, nil)
             |> close()
             |> notice("controllers.places.destroyed")
             |> push_event("map:invalidate", %{resource: "places"})}

          {:error, :not_found} ->
            {:noreply, close(socket)}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp load(socket, id) do
    case Places.detail(socket.assigns.current_scope, id) do
      {:ok, detail} ->
        socket = assign(socket, :place_detail, detail)

        case Places.edit(socket.assigns.current_scope, detail.id) do
          {:ok, place} ->
            socket
            |> push_event("map:layer", %{layer: "places", enabled: true})
            |> push_event("place:focus", %{latitude: place.latitude, longitude: place.longitude})

          _ ->
            socket
        end

      _ ->
        assign(socket, place_detail: nil, place_dialog: nil)
    end
  end

  defp close(socket),
    do:
      socket
      |> assign(:place_detail, nil)
      |> push_patch(to: Commands.path(socket.assigns.map_url, %{"place_id" => nil}))

  defp notice(socket, key),
    do: put_flash(socket, :notice, DawarichWeb.Translate.t(socket.assigns.locale, key, %{}))
end
