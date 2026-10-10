defmodule Dawarich.Test.NativeMapShellProbe do
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}
  alias DawarichWeb.MapLive.Commands

  def mount(_, _, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    {:ok, page} =
      Dawarich.Maps.page(socket.assigns.current_scope, params,
        now: socket.assigns.now,
        self_hosted: true,
        family: false,
        env: %{}
      )

    {:noreply, socket |> assign(:page, page) |> Commands.apply_params(params, page.window)}
  end

  def handle_event("area:" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.AreaCommands.handle_event(event, payload, socket)

  def handle_event("segment" <> _ = event, payload, socket),
    do: DawarichWeb.MapLive.SegmentCommands.handle_event(event, payload, socket)

  def handle_event(event, payload, socket), do: Commands.handle_event(event, payload, socket)

  def render(assigns) do
    ~H"""
    <output id="state">{Jason.encode!(%{url: @map_url, revision: @map_revision})}</output>
    <DawarichWeb.NativeMapControls.date_navigation
      url={@map_url}
      window={@page.window}
      locale="en"
    />
    <DawarichWeb.NativeAreaDialog.dialog dialog={assigns[:area_dialog]} locale="en" />
    <DawarichWeb.NativeSegmentEditor.drawer drawer={assigns[:segment_drawer]} locale="en" />
    """
  end
end

defmodule Dawarich.Test.NativeMapShellRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :probe do
    plug DawarichWeb.RailsAuth
    plug :fetch_live_flash
  end

  scope "/" do
    pipe_through :probe

    live_session :map_shell_probe, session: {DawarichWeb.MapLiveAuth, :live_session, []} do
      live "/map/v2", Dawarich.Test.NativeMapShellProbe
    end
  end
end
