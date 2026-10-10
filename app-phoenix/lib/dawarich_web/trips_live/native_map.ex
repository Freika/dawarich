defmodule DawarichWeb.TripsLive.NativeMap do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, socket),
    do: {:ok, socket |> DawarichWeb.NativePosterGallery.mount(), layout: false}

  def handle_params(%{"id" => id}, _, socket) do
    trip_id = Dawarich.RubyInteger.to_i(id)

    case Dawarich.Maps.Dependencies.Trip.view(socket.assigns.current_scope, trip_id) do
      {:ok, page} ->
        config = page.config
        label = config["range"]["startAt"] <> " – " <> config["range"]["endAt"]

        {:noreply,
         assign(socket, page: Map.put(page, :range_label, label), page_title: config["title"])}

      {:error, reason} ->
        {:noreply, DawarichWeb.MapLiveAuth.refuse(assign(socket, :page_title, nil), reason)}
    end
  end

  def handle_event("poster:" <> _ = event, payload, socket),
    do: DawarichWeb.NativePosterGallery.handle_event(event, payload, socket)

  def handle_event(event, _, socket) when event in ~w(map:ready map:failed trip:day),
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
      <DawarichWeb.NativeTripContent.content page={@page.presentation} locale={@locale} />
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
