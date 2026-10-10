defmodule DawarichWeb.OnboardingLiveComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_new(:completed, fn -> false end)}
  end

  def handle_event("onboarding:complete", _params, socket) do
    case Dawarich.Onboarding.complete(socket.assigns.scope) do
      :ok -> {:noreply, assign(socket, :completed, true)}
      _ -> {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <DawarichWeb.NativeOnboarding.modal
        current_user={@scope.user}
        navbar={@navbar}
        locale={@locale}
        base_url={@base_url}
        rails_csrf_token={@rails_csrf_token}
        auto_open={@auto_open and not @completed}
        target={@myself}
      />
    </div>
    """
  end
end
