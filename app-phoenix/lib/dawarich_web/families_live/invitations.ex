defmodule DawarichWeb.FamiliesLive.Invitations do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.FamilyInvitations, only: [invitation_index: 1]

  @impl true
  def mount(_params, _session, socket) do
    case Dawarich.FamilyPage.read(socket.assigns.current_user, :invitations,
           now: socket.assigns.now,
           self_hosted: socket.assigns.self_hosted
         ) do
      {:ok, page} -> {:ok, assign(socket, page: page, page_title: nil, rails_js: true)}
      {:redirect, path, _reason} -> {:ok, redirect(socket, to: path)}
      _other -> {:ok, redirect(socket, to: "/family/invitations")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="family-invitations-shell"
      class="contents"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-turbo="true"
    >
      <.invitation_index
        page={@page}
        locale={@locale}
        base_url={@base_url}
        self_hosted={@self_hosted}
      />
    </div>
    """
  end
end
