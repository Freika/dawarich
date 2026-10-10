defmodule DawarichWeb.TripsLive.NativeMap do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, socket),
    do:
      {:ok,
       socket
       |> assign(selected_day: nil, note_editor: nil, expanded_days: false, trip_layers: %{})
       |> DawarichWeb.NativePosterGallery.mount(), layout: false}

  def handle_params(%{"id" => id}, _, socket) do
    socket =
      assign(socket, selected_day: nil, note_editor: nil, expanded_days: false, trip_layers: %{})

    case DawarichWeb.NativeTripState.refresh(socket, Dawarich.RubyInteger.to_i(id)) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

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
      :unhandled -> {:noreply, socket}
      result -> result
    end
  end

  def render(assigns) do
    ~H"""
    <main :if={@page} id="trip-shell" data-native-map-root class="w-full min-w-0 p-4">
      <DawarichWeb.NativeTripToolbar.toolbar page={@page} expanded={@expanded_days} locale={@locale} />
      <DawarichWeb.NativeTripContent.content
        page={@page.presentation}
        locale={@locale}
        selected_day={@selected_day}
        note_editor={@note_editor}
        expanded_days={@expanded_days}
        plan_enabled={@page.config["planEnabled"]}
      />
      <p>{@page.range_label}</p>
      <DawarichWeb.NativeTripMapPanel.panel config={@page.config} locale={@locale} />
      <DawarichWeb.NativePosterStudio.poster_studio
        themes={@page.studio.themes}
        posters={@posters}
        print_order_url={@page.studio.print_order_url}
        locale={@locale}
        fixed_range_label={@page.range_label}
      />
      <.live_component
        module={DawarichWeb.VideoStudioLiveComponent}
        id="video-studio-owner"
        scope={@current_scope}
        locale={@locale}
        base_url={assigns[:base_url] || ""}
        themes={@page.studio.themes}
        fixed_range_label={@page.range_label}
      />
    </main>
    <p :if={@map_error} role="alert">{to_string(@map_error)}</p>
    """
  end
end
