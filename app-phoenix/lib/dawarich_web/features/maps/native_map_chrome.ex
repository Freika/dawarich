defmodule DawarichWeb.NativeMapChrome do
  @moduledoc false
  use DawarichWeb, :html
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3]

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

  def refresh(socket) do
    navbar =
      Dawarich.Maps.with_actor(socket.assigns.current_scope, fn actor ->
        Dawarich.Navbar.load(actor,
          now: socket.assigns.now,
          self_hosted: socket.assigns.self_hosted != false
        )
      end)

    socket = assign(socket, :navbar, navbar)

    if socket.view == DawarichWeb.MapLive.Native and is_map(navbar) and
         is_map(socket.assigns[:map_config]) and is_map(socket.assigns[:page]) do
      page =
        Map.put(socket.assigns.page, :family, navbar.family.available and navbar.family.member)

      config =
        DawarichWeb.MapLive.NativeConfig.build(
          socket.assigns[:map_settings],
          page,
          socket.assigns.map_config,
          socket.assigns.map_url["panel"]
        )

      socket |> assign(page: page, map_config: config) |> push_event("map:config", config)
    else
      socket
    end
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

  defp event(_, _, socket), do: {:cont, refresh(socket)}

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
    <DawarichWeb.Chrome.achievement_host
      :if={@page && @current_scope && @navbar}
      user_id={@current_user.id}
      native
    />
    """
  end
end
