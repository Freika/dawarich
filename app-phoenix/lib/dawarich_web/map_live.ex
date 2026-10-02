defmodule DawarichWeb.MapLive do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.MapIndex, only: [map_page: 1]

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok, assign(socket, :page_title, t(socket.assigns.locale, "map.maplibre.index.map", %{}))}

  @impl true
  def handle_params(params, uri, socket) do
    %{current_user: user, now: now, self_hosted: self_hosted, navbar: navbar} = socket.assigns

    case Dawarich.MapPage.load(user, params,
           now: now,
           self_hosted: self_hosted,
           family: navbar.family.available
         ) do
      {:ok, page} -> {:noreply, assign(socket, page: page, params: params)}
      :not_found -> not_found(socket, uri)
    end
  end

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, DawarichWeb.RailsWidgets.rails_flash(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <.map_page
      page={@page}
      params={@params}
      locale={@locale}
      base_url={@base_url || ""}
      self_hosted={@self_hosted}
      rails_csrf_token={@rails_csrf_token}
      now={@now}
    />
    """
  end

  defp not_found(socket, uri) do
    if connected?(socket) do
      %URI{path: path, query: query} = URI.parse(uri)
      {:noreply, redirect(socket, to: if(query, do: path <> "?" <> query, else: path))}
    else
      raise DawarichWeb.NotFoundError
    end
  end
end
