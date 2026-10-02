defmodule DawarichWeb.InsightsLive.Details do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Insights.{Details, Fragments}
  alias DawarichWeb.InsightsDetails.Body

  @impl true
  def mount(params, _session, socket) do
    opts = [
      now: socket.assigns.now,
      self_hosted: socket.assigns.self_hosted,
      read_only: connected?(socket)
    ]

    data = Details.load(socket.assigns.current_user, params, opts)

    fragments =
      if data.restricted,
        do: %{},
        else: Fragments.render(socket.assigns.current_user, socket.assigns.locale, data, opts)

    socket = assign(socket, data: data, fragments: fragments, rails_js: true, page_title: nil)
    layout = if socket.assigns.insights_frame, do: false, else: {DawarichWeb.Layouts, :app}
    {:ok, socket, layout: layout}
  end

  @impl true
  def render(assigns), do: Body.render(assigns)
  @impl true
  def handle_info(:navbar_refresh, socket), do: {:noreply, socket}
end
