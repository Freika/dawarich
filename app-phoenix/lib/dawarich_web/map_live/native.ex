defmodule DawarichWeb.MapLive.Native do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}
  alias DawarichWeb.MapLive.Commands

  def mount(_, _, socket) do
    navbar =
      Dawarich.Maps.with_actor(socket.assigns.current_scope, fn actor ->
        Dawarich.Navbar.load(actor,
          now: socket.assigns.now,
          self_hosted: socket.assigns.self_hosted != false
        )
      end)

    {:ok, socket |> assign(:navbar, navbar) |> DawarichWeb.MapLive.SettingsCommands.load(), layout: false}
  end

  def handle_params(params, _uri, socket) do
    opts = [
      now: socket.assigns.now,
      self_hosted: socket.assigns.self_hosted != false,
      family: false
    ]

    case Dawarich.Maps.page(socket.assigns.current_scope, params, opts) do
      {:ok, page} ->
        previous = socket.assigns[:map_revision]
        old_panel = (socket.assigns[:map_url] || %{})["panel"]

        socket =
          socket
          |> assign(page: page, params: params)
          |> Commands.apply_params(params, page.window)

        config = %{
          "namespace" => "user:#{socket.assigns.current_user.id}",
          "revision" => socket.assigns.map_revision,
          "range" =>
            socket.assigns.map_range
            |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
        }

        socket = assign(socket, :map_config, config)
        socket = if previous != socket.assigns.map_revision, do: DawarichWeb.MapLive.EnrichmentCommands.cancel(socket), else: socket

        socket =
          if connected?(socket) and params["panel"] == "timeline" and
               (previous != socket.assigns.map_revision or old_panel != "timeline"),
             do: DawarichWeb.MapLive.Timeline.refresh(socket, params),
             else: socket

        socket =
          if connected?(socket) and params["panel"] == "timeline" and
               (previous != socket.assigns.map_revision or old_panel != "timeline") do
            {:noreply, next} =
              DawarichWeb.MapLive.TimelineFilters.handle_event(
                "calendar:month",
                %{"month" => page.window.calendar_month},
                socket
              )

            next
          else
            socket
          end

        socket =
          if params["panel"] == "insights" and old_panel != "insights" do
            {:noreply, next} =
              DawarichWeb.MapLive.TimelineFilters.handle_event("residency:year", %{}, socket)

            next
          else
            socket
          end

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, DawarichWeb.MapLiveAuth.refuse(socket, reason)}
    end
  end

  def handle_event("map:select", %{"kind" => "area", "id" => id}, socket),
    do: DawarichWeb.MapLive.AreaCommands.handle_event("area:edit", %{"id" => id}, socket)

  def handle_event("map:select", %{"kind" => kind, "id" => id}, socket) when kind in ~w(place visit),
    do: DawarichWeb.MapLive.EntityCommands.handle_event(kind <> ":edit", %{"id" => id}, socket)

  def handle_event("timeline:filter", payload, socket),
    do: {:noreply, DawarichWeb.MapLive.Timeline.filter(socket, payload)}

  def handle_event("place:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_event(event, payload, socket)

  def handle_event("visit:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_event(event, payload, socket)

  def handle_event("visits:merge" = event, payload, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_event(event, payload, socket)

  def handle_event("note:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_event(event, payload, socket)

  def handle_event("address:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_event(event, payload, socket)

  def handle_event("settings:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.SettingsCommands.handle_event(event, payload, socket)

  def handle_event("enrichment:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.EnrichmentCommands.handle_event(event, payload, socket)

  def handle_event("point" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.PointCommands.handle_event(event, payload, socket)

  def handle_event("calendar:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.TimelineFilters.handle_event(event, payload, socket)

  def handle_event("residency:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.TimelineFilters.handle_event(event, payload, socket)

  def handle_event("segment" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.SegmentCommands.handle_event(event, payload, socket)

  def handle_event("area:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.AreaCommands.handle_event(event, payload, socket)

  def handle_event(event, payload, socket) when event in ~w(map:range map:dates map:panel),
    do: Commands.handle_event(event, payload, socket)

  def handle_event(event, _, socket) when event in ~w(map:ready map:failed),
    do: {:noreply, socket}

  def handle_async({:timeline, _} = name, result, socket),
    do: DawarichWeb.MapLive.Timeline.handle_async(name, result, socket)

  def handle_async({:calendar, _} = name, result, socket),
    do: DawarichWeb.MapLive.TimelineFilters.handle_async(name, result, socket)

  def handle_async({:enrichment_scan, _} = name, result, socket),
    do: DawarichWeb.MapLive.EnrichmentCommands.handle_async(name, result, socket)

  def handle_async({:place_nearby, _} = name, result, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_async(name, result, socket)

  def handle_async({:visit_places, _} = name, result, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_async(name, result, socket)

  def render(assigns) do
    ~H"""
    <div :if={@page} id="native-map-page" class="relative w-full min-w-0 h-[100dvh] flex flex-col">
      <DawarichWeb.NativeMapControls.date_navigation
        url={@map_url}
        window={@page.window}
        locale={@locale}
      />
      <div class="min-w-0 max-w-full">
        <input data-map-search type="search" class="input input-bordered max-w-full" aria-label={t(@locale, "javascript.search.search_placeholder", %{})} />
        <ul data-map-suggestions role="listbox" class="min-w-0 [overflow-wrap:anywhere]" phx-update="ignore" id="native-map-suggestions"></ul>
        <section data-map-search-visits id="native-map-search-visits" phx-update="ignore" class="min-w-0 max-w-full"></section>
      </div>
      <button type="button" data-testid="native-create-area" class="btn btn-sm">{t(
        @locale,
        "javascript.areas.create_new",
        %{}
      )}</button>
      <section
        :if={@map_url["panel"] == "timeline"}
        id="native-map-panel"
        class="absolute left-0 top-40 bottom-0 z-10 overflow-auto w-96 max-w-full min-w-0 bg-base-100 p-3"
      >
        <DawarichWeb.NativeTimelineCalendar.calendar calendar={assigns[:calendar]} locale={@locale} />
        <DawarichWeb.NativeTimelineFeed.feed timeline={assigns[:timeline]} filter={assigns[:timeline_filter]} locale={@locale} />
      </section>
      <DawarichWeb.NativeResidency.card
        :if={@map_url["panel"] == "insights"}
        residency={assigns[:residency]}
        locale={@locale}
      />
      <button type="button" data-testid="native-select-area" class="btn btn-sm">{t(@locale, "javascript.selection.select_area", %{})}</button>
      <section id="native-map-selection" data-map-selection phx-update="ignore" class="min-w-0 max-w-full" tabindex="0"></section>
      <DawarichWeb.NativeMapVisit.dialog dialog={assigns[:visit_dialog]} locale={@locale} />
      <DawarichWeb.NativePointAddress.drawer address={assigns[:point_address]} locale={@locale} />
      <button type="button" data-testid="native-create-visit" class="btn btn-sm">{t(@locale, "javascript.visits.create_new", %{})}</button>
      <DawarichWeb.NativeMapPlace.dialog dialog={assigns[:place_dialog]} locale={@locale} />
      <button type="button" data-testid="native-create-place" class="btn btn-sm">{t(@locale, "javascript.places.create_new", %{})}</button>
      <DawarichWeb.NativeMapSettings.panel
        :if={@map_url["panel"] == "settings"}
        settings={assigns[:map_settings]}
        locale={@locale}
      />
      <DawarichWeb.NativeMapEnrichment.tool
        :if={@map_url["panel"] == "tools" && @page.full_access && @page.immich}
        enrichment={assigns[:enrichment]}
        start_date={String.slice(@page.window.start, 0, 10)}
        end_date={String.slice(@page.window.end, 0, 10)}
        locale={@locale}
      />
      <DawarichWeb.NativeSegmentEditor.drawer drawer={assigns[:segment_drawer]} locale={@locale} />
      <DawarichWeb.NativeAreaDialog.dialog dialog={assigns[:area_dialog]} locale={@locale} />
      <div class="relative flex-1 min-h-0 min-w-0">
        <DawarichWeb.NativeMapHost.map_host id="native-map" config={@map_config} locale={@locale} />
      </div>
    </div>
    <.live_component
      :if={@current_scope && @page}
      module={DawarichWeb.OnboardingLiveComponent}
      id="onboarding"
      scope={@current_scope}
      navbar={@navbar}
      locale={@locale}
      base_url={assigns[:base_url] || ""}
      rails_csrf_token=""
      auto_open={true}
    />
    <div :if={@map_error} role="alert">{to_string(@map_error)}</div>
    """
  end
end
