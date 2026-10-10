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

    {:ok, assign(socket, :navbar, navbar), layout: false}
  end

  def handle_params(params, _uri, socket) do
    opts = [
      now: socket.assigns.now,
      self_hosted: socket.assigns.self_hosted != false,
      family: false
    ]

    case Dawarich.Maps.page(socket.assigns.current_scope, params, opts) do
      {:ok, page} ->
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

        {:noreply, assign(socket, :map_config, config)}

      {:error, reason} ->
        {:noreply, DawarichWeb.MapLiveAuth.refuse(socket, reason)}
    end
  end

  def handle_event("map:select", %{"kind" => "area", "id" => id}, socket),
    do: DawarichWeb.MapLive.AreaCommands.handle_event("area:edit", %{"id" => id}, socket)

  def handle_event("area:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.AreaCommands.handle_event(event, payload, socket)

  def handle_event(event, payload, socket) when event in ~w(map:range map:dates map:panel),
    do: Commands.handle_event(event, payload, socket)

  def handle_event(event, _, socket) when event in ~w(map:ready map:failed),
    do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div :if={@page} id="native-map-page" class="relative w-full min-w-0 h-[100dvh] flex flex-col">
      <DawarichWeb.NativeMapControls.date_navigation
        url={@map_url}
        window={@page.window}
        locale={@locale}
      />
      <button type="button" data-testid="native-create-area" class="btn btn-sm">{t(
        @locale,
        "javascript.areas.create_new",
        %{}
      )}</button>
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
