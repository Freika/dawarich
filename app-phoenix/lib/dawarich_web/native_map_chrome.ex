defmodule DawarichWeb.NativeMapChrome do
  @moduledoc false
  use DawarichWeb, :html
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  def load(socket) do
    if connected?(socket) do
      Dawarich.Families.subscribe_changes(socket.assigns.current_scope)
      Dawarich.Notifications.subscribe(socket.assigns.current_scope)
    end

    socket
    |> refresh()
    |> attach_hook(:native_chrome, :handle_event, &event/3)
    |> attach_hook(:native_chrome_info, :handle_info, &info/2)
  end

  defp refresh(socket) do
    navbar =
      Dawarich.Maps.with_actor(socket.assigns.current_scope, fn actor ->
        Dawarich.Navbar.load(actor,
          now: socket.assigns.now,
          self_hosted: socket.assigns.self_hosted != false
        )
      end)

    assign(socket, :navbar, navbar)
  end

  defp info({:domain_changed, owner, kind}, socket)
       when owner == socket.assigns.current_user.id and
              kind in [:membership, :consent, :request, :invitation, :lapse, :notifications],
       do: {:cont, refresh(socket)}

  defp info(_, socket), do: {:cont, socket}

  defp event("changelog_consent", %{"decision" => decision}, socket)
       when decision in ~w(granted declined) do
    Dawarich.Maps.with_actor(
      socket.assigns.current_scope,
      &Dawarich.Navbar.put_changelog_consent(&1, decision)
    )

    {:halt, refresh(socket)}
  end

  defp event(_, _, socket), do: {:cont, socket}

  def header(assigns) do
    ~H"""
    <DawarichWeb.Navbar.navbar
      :if={@page && @current_scope && @navbar}
      current_user={@current_user}
      data={@navbar}
      locale={@locale}
      request_path={@request_path || "/"}
      base_url={@base_url || ""}
      self_hosted={@self_hosted != false}
      rails_csrf_token={assigns[:rails_csrf_token]}
      now={@now}
      native
    />
    """
  end
end
