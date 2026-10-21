defmodule DawarichWeb.NativeTripResource do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  def attach(socket) do
    socket
    |> attach_hook(:native_trip_event, :handle_event, fn _, _, socket -> authorize(socket) end)
    |> attach_hook(:native_trip_info, :handle_info, fn _, socket -> authorize(socket) end)
    |> attach_hook(:native_trip_async, :handle_async, fn _, _, socket -> authorize(socket) end)
  end

  def authorize(%{assigns: %{page: nil}} = socket), do: {:cont, socket}

  def authorize(socket) do
    case Dawarich.Maps.Trip.admit(
           socket.assigns.current_scope,
           socket.assigns.page.presentation.id
         ) do
      :ok -> {:cont, socket}
      {:error, reason} -> {:halt, refuse(socket, reason)}
    end
  end

  def refuse(socket, reason) do
    socket
    |> assign(
      page_title: nil,
      trip_confirmation: nil,
      selected_day: nil,
      note_editor: nil,
      trip_layers: %{},
      expanded_days: false,
      posters: []
    )
    |> DawarichWeb.MapLiveAuth.refuse(reason)
    |> push_event("map:clear", %{code: Atom.to_string(reason)})
  end
end
