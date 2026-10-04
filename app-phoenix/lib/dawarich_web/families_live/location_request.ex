defmodule DawarichWeb.FamiliesLive.LocationRequest do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.FamilyRequestForms, only: [location_request: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Dawarich.FamilyPage.read(socket.assigns.current_user, {:request, String.to_integer(id)},
           now: socket.assigns.now,
           self_hosted: socket.assigns.self_hosted
         ) do
      {:ok, page} -> {:ok, assign(socket, page: page, page_title: nil, rails_js: true)}
      {:redirect, path, _reason} -> {:ok, redirect(socket, to: path)}
      _other -> {:ok, redirect(socket, to: "/family/location_requests/" <> id)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="family-request-shell"
      class="contents"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-turbo="true"
    >
      <.location_request
        page={@page}
        locale={@locale}
        now={@now}
        rails_csrf_token={@rails_csrf_token}
      />
    </div>
    """
  end
end
