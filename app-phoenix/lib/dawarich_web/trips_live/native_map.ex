defmodule DawarichWeb.TripsLive.NativeMap do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, %{assigns: %{current_scope: nil}} = socket),
    do:
      {:ok,
       assign(socket,
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
       |> assign(selected_day: nil, note_editor: nil, expanded_days: false, trip_layers: %{})
       |> DawarichWeb.NativePosterGallery.mount()
       |> DawarichWeb.NativeTripResource.attach()
       |> DawarichWeb.NativeMapChrome.load(), layout: false}

  def handle_params(%{"id" => id}, _, socket) do
    socket =
      assign(socket, selected_day: nil, note_editor: nil, expanded_days: false, trip_layers: %{})

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
      when event in ~w(trip:delete trip:recalculate trip:export),
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

  def render(assigns) do
    ~H"""
    <DawarichWeb.NativeMapChrome.header {assigns} />
    <DawarichWeb.Chrome.flash locale={@locale} flash={@flash} native={true} />
    <main :if={@page} id="trip-shell" data-native-map-root class="w-full min-w-0 p-4">
      <div class="flex min-w-0 flex-col gap-6 lg:flex-row lg:h-[calc(100dvh-9.75rem)]">
        <div class="w-full min-w-0 lg:w-3/5 h-[50vh] lg:h-full shrink-0">
          <DawarichWeb.NativeTripMapPanel.panel
            config={@page.config}
            locale={@locale}
            state={@page.presentation.map_state}
            has_path={@page.presentation.has_path}
            future={@page.presentation.future_start}
          />
        </div>
        <div class="w-full min-w-0 lg:w-2/5 lg:h-full lg:overflow-y-auto">
          <DawarichWeb.NativeTripActions.actions page={@page.presentation} locale={@locale} />
          <DawarichWeb.NativeTripToolbar.toolbar
            page={@page}
            expanded={@expanded_days}
            locale={@locale}
          />
          <DawarichWeb.NativeTripContent.content
            page={@page.presentation}
            locale={@locale}
            selected_day={@selected_day}
            note_editor={@note_editor}
            expanded_days={@expanded_days}
            plan_enabled={@page.config["planEnabled"]}
          />
          <p>{@page.range_label}</p>
        </div>
      </div>
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
