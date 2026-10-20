defmodule DawarichWeb.MapLive.Native do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}
  alias DawarichWeb.MapLive.Commands

  def mount(_, _, %{assigns: %{current_scope: nil}} = socket),
    do: {:ok, assign(socket, navbar: nil, posters: [], map_settings: nil), layout: false}

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(:page_title, t(socket.assigns.locale, "map.maplibre.index.map", %{}))
     |> assign(:body_class, "h-screen !h-[100dvh] overflow-hidden relative")
     |> DawarichWeb.NativeMapChrome.load(refresh: false)
     |> DawarichWeb.MapLive.SettingsCommands.load()
     |> DawarichWeb.NativePosterGallery.mount(), layout: false}
  end

  def handle_params(params, _uri, socket) do
    socket = DawarichWeb.NativeMapChrome.refresh(socket)

    opts = [
      now: socket.assigns.now,
      self_hosted: socket.assigns.self_hosted != false,
      family: socket.assigns.navbar.family.available and socket.assigns.navbar.family.member
    ]

    case Dawarich.Maps.page(socket.assigns.current_scope, params, opts) do
      {:ok, page} ->
        previous = socket.assigns[:map_revision]
        old_date = (socket.assigns[:map_url] || %{})["date"]
        old_panel = (socket.assigns[:map_url] || %{})["panel"]
        old_visit = (socket.assigns[:map_url] || %{})["visit_id"]

        socket =
          socket
          |> assign(page: page, params: params)
          |> Commands.apply_params(params, page.window)

        config =
          Map.merge(socket.assigns[:map_config] || %{}, %{
            "namespace" => "user:#{socket.assigns.current_user.id}",
            "revision" => socket.assigns.map_revision,
            "range" =>
              socket.assigns.map_range
              |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
          })

        config =
          DawarichWeb.MapLive.NativeConfig.build(
            socket.assigns[:map_settings],
            page,
            config,
            params["panel"]
          )

        socket =
          socket
          |> assign(:map_config, config)
          |> push_event("map:config", config)
          |> DawarichWeb.MapLive.Subscriptions.sync(%{
            kind: :map,
            scope: socket.assigns.current_scope
          })

        socket =
          if previous != socket.assigns.map_revision,
            do: DawarichWeb.MapLive.EnrichmentCommands.cancel(socket),
            else: socket

        socket =
          if previous != socket.assigns.map_revision or old_panel != params["panel"] or
               old_date != params["date"],
             do: DawarichWeb.MapLive.TrackCommands.clear(socket),
             else: socket

        socket = DawarichWeb.MapLive.TrackCommands.resume(socket)

        socket =
          DawarichWeb.MapLive.VisitNavigation.params(
            socket,
            previous != socket.assigns.map_revision or old_panel != params["panel"] or
              old_date != params["date"] or old_visit != params["visit_id"]
          )

        socket =
          if connected?(socket) and params["panel"] == "timeline" and
               (previous != socket.assigns.map_revision or old_panel != "timeline"),
             do:
               DawarichWeb.MapLive.Timeline.refresh(socket, %{
                 "start_at" => page.window.start,
                 "end_at" => page.window.end
               }),
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

        {:noreply, DawarichWeb.MapLive.VisitNavigation.hydrate(socket)}

      {:error, reason} ->
        {:noreply, DawarichWeb.MapLiveAuth.refuse(socket, reason)}
    end
  end

  def handle_event("poster:" <> _ = event, payload, socket),
    do: DawarichWeb.NativePosterGallery.handle_event(event, payload, socket)

  def handle_event(event, payload, socket)
      when event in ~w(map:visits_filter map:flights map:anomalies),
      do: DawarichWeb.MapLive.LayerCommands.handle_event(event, payload, socket)

  def handle_event("map:select", %{"kind" => "track", "id" => id}, socket),
    do: DawarichWeb.MapLive.TrackCommands.handle_event("track:from_map", %{"id" => id}, socket)

  def handle_event("track:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.TrackCommands.handle_event(event, payload, socket)

  def handle_event("map:select", %{"kind" => "area", "id" => id}, socket),
    do: DawarichWeb.MapLive.AreaCommands.handle_event("area:edit", %{"id" => id}, socket)

  def handle_event("map:select", %{"kind" => "visit", "id" => id}, socket),
    do: DawarichWeb.MapLive.VisitNavigation.select(socket, id)

  def handle_event("visit:select", %{"id" => id}, socket),
    do: DawarichWeb.MapLive.VisitNavigation.select(socket, id)

  def handle_event("visits:bulk" = event, payload, socket),
    do: DawarichWeb.MapLive.VisitBulkCommands.handle_event(event, payload, socket)

  def handle_event("timeline:select" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.VisitBulkCommands.handle_event(event, payload, socket)

  def handle_event("timeline:more", _, socket),
    do: {:noreply, DawarichWeb.MapLive.Timeline.more(socket)}

  def handle_event("timeline:tag", payload, socket),
    do: {:noreply, DawarichWeb.MapLive.Timeline.toggle_tag(socket, payload)}

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

  def handle_event("settings:" <> _ = event, payload, socket) do
    {:noreply, socket} = DawarichWeb.MapLive.SettingsCommands.handle_event(event, payload, socket)

    config =
      DawarichWeb.MapLive.NativeConfig.build(
        socket.assigns[:map_settings],
        socket.assigns.page,
        socket.assigns.map_config,
        socket.assigns.map_url["panel"]
      )

    {:noreply,
     socket
     |> assign(:map_config, config)
     |> push_event("map:config", config)
     |> DawarichWeb.MapLive.Subscriptions.sync(%{
       kind: :map,
       scope: socket.assigns.current_scope
     })}
  end

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

  def handle_event(_event, _payload, socket), do: {:noreply, socket}

  def handle_info({DawarichWeb.VideoStudioLiveComponent, {:saved, _id, _evicted}}, socket),
    do: {:noreply, socket}

  def handle_info(message, socket) do
    case DawarichWeb.NativePosterGallery.handle_info(message, socket) do
      :unhandled ->
        {_, socket} = DawarichWeb.MapLive.Subscriptions.deliver(socket, message)
        {:noreply, socket}

      result ->
        result
    end
  end

  def handle_async({:timeline, _} = name, result, socket) do
    {:noreply, socket} = DawarichWeb.MapLive.Timeline.handle_async(name, result, socket)

    {:noreply,
     socket
     |> DawarichWeb.MapLive.VisitNavigation.hydrate()}
  end

  def handle_async({:calendar, _} = name, result, socket),
    do: DawarichWeb.MapLive.TimelineFilters.handle_async(name, result, socket)

  def handle_async({:enrichment_scan, _} = name, result, socket),
    do: DawarichWeb.MapLive.EnrichmentCommands.handle_async(name, result, socket)

  def handle_async({:place_nearby, _} = name, result, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_async(name, result, socket)

  def handle_async({:visit_places, _} = name, result, socket),
    do: DawarichWeb.MapLive.EntityCommands.handle_async(name, result, socket)

  def render(assigns), do: DawarichWeb.NativeMapPage.page(assigns)
end
