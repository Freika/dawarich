defmodule DawarichWeb.TripsLive.NativeMap do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, %{assigns: %{current_scope: nil}} = socket),
    do:
      {:ok,
       assign(socket,
         trip_confirmation: nil,
         selected_day: nil,
         note_editor: nil,
         expanded_days: false,
         trip_layers: %{},
         posters: []
       ), layout: false}

  def mount(_, _, socket),
    do:
      {:ok,
       socket
       |> assign(
         trip_confirmation: nil,
         selected_day: nil,
         note_editor: nil,
         expanded_days: false,
         trip_layers: %{}
       )
       |> DawarichWeb.NativePosterGallery.mount()
       |> DawarichWeb.NativeTripResource.attach()
       |> DawarichWeb.NativeMapChrome.load()
       |> assign(
         body_class: "min-h-screen flex flex-col",
         viewport: "width=device-width,initial-scale=1"
       ), layout: false}

  def handle_params(%{"id" => id}, _, socket) do
    socket =
      assign(socket,
        trip_confirmation: nil,
        selected_day: nil,
        note_editor: nil,
        expanded_days: false,
        trip_layers: %{}
      )

    case DawarichWeb.NativeTripState.load(socket, DawarichWeb.NativeTripState.identity(id)) do
      {:ok, socket} ->
        descriptor = %{
          kind: :trip,
          scope: socket.assigns.current_scope,
          trip_id: socket.assigns.page.presentation.id
        }

        {:noreply, DawarichWeb.MapLive.Subscriptions.sync(socket, descriptor)}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event(event, payload, socket)
      when event in ~w(trip:delete trip:recalculate trip:note:delete),
      do: DawarichWeb.NativeTripConfirmation.open(event, payload, socket)

  def handle_event("trip:confirmation:accept", _, socket),
    do: DawarichWeb.NativeTripConfirmation.accept(socket)

  def handle_event("trip:confirmation:cancel", _, socket),
    do: DawarichWeb.NativeTripConfirmation.cancel(socket)

  def handle_event(event, payload, socket)
      when event == "trip:export",
      do: DawarichWeb.NativeTripEffects.handle_event(event, payload, socket)

  def handle_event(event, payload, socket)
      when event in ~w(trip:layer trip:days:all trip:plan:focus),
      do: DawarichWeb.NativeTripControls.handle_event(event, payload, socket)

  def handle_event("trip:note:" <> _ = event, payload, socket),
    do: DawarichWeb.NativeTripNotes.handle_event(event, payload, socket)

  def handle_event("trip:day", %{"day" => day}, socket) do
    case DawarichWeb.NativeTripState.refresh(socket) do
      {:ok, socket} ->
        if DawarichWeb.NativeTripState.day(socket, day) do
          selected = if socket.assigns.selected_day == day, do: nil, else: day

          {:noreply,
           socket
           |> assign(:selected_day, selected)
           |> push_event("trip:select_day", %{day: selected})}
        else
          {:noreply, assign(socket, :selected_day, nil)}
        end

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("poster:" <> _ = event, payload, socket),
    do: DawarichWeb.NativePosterGallery.handle_event(event, payload, socket)

  def handle_event(event, _, socket) when event in ~w(map:ready map:failed),
    do: {:noreply, socket}

  def handle_info({DawarichWeb.VideoStudioLiveComponent, {:saved, _id, _evicted}}, socket),
    do: {:noreply, socket}

  def handle_info(message, socket) do
    case DawarichWeb.NativePosterGallery.handle_info(message, socket) do
      :unhandled ->
        case DawarichWeb.MapLive.Subscriptions.deliver(socket, message) do
          {:delivered, socket} ->
            case DawarichWeb.NativeTripState.refresh(socket) do
              {:ok, socket} -> {:noreply, socket}
              {:error, socket} -> {:noreply, socket}
            end

          {:refused, socket} ->
            {:noreply, DawarichWeb.NativeTripResource.refuse(socket, :not_found)}

          {_, socket} ->
            {:noreply, socket}
        end

      result ->
        result
    end
  end

  def render(assigns), do: DawarichWeb.NativeTripDocument.render(assigns)
end
