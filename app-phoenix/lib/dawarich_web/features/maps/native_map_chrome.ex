defmodule DawarichWeb.NativeMapChrome do
  @moduledoc false
  use DawarichWeb, :html
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3]

  def load(socket, opts \\ []) do
    if connected?(socket) do
      Dawarich.Families.subscribe_changes(socket.assigns.current_scope)
      Dawarich.Notifications.subscribe(socket.assigns.current_scope)
    end

    socket
    |> assign(:body_class, "h-screen !h-[100dvh] overflow-hidden relative")
    |> assign(:viewport, "width=device-width,initial-scale=1,viewport-fit=cover")
    |> then(&if(Keyword.get(opts, :refresh, true), do: refresh(&1), else: &1))
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

      changed = config != socket.assigns.map_config
      socket = assign(socket, page: page, map_config: config)
      if changed, do: push_event(socket, "map:config", config), else: socket
    else
      socket
    end
  end

  defp info({:domain_changed, owner, :notifications}, socket)
       when owner == socket.assigns.current_user.id do
    coalesce(owner, 100)

    case Dawarich.Notifications.unread(socket.assigns.current_scope) do
      {:ok, unread} ->
        {:cont, assign(socket, :navbar, Map.put(socket.assigns.navbar, :unread, unread))}

      _ ->
        {:halt, DawarichWeb.NotificationSession.Native.refuse(socket)}
    end
  end

  defp info({:domain_changed, owner, kind}, socket)
       when owner == socket.assigns.current_user.id and
              kind in [:membership, :consent, :request, :invitation, :lapse],
       do: {:cont, refresh(socket)}

  defp info(_, socket), do: {:cont, socket}

  defp coalesce(_, 0), do: :ok

  defp coalesce(owner, remaining) do
    receive do
      {:domain_changed, ^owner, :notifications} -> coalesce(owner, remaining - 1)
    after
      0 -> :ok
    end
  end

  defp event("changelog_consent", %{"decision" => decision}, socket)
       when decision in ~w(granted declined) do
    Dawarich.Maps.with_actor(
      socket.assigns.current_scope,
      &Dawarich.Navbar.put_changelog_consent(&1, decision)
    )

    {:halt, refresh(socket)}
  end

  defp event(event, _, socket) when event in ~w(map:ready map:failed), do: {:cont, socket}
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
    <DawarichWeb.Chrome.achievement_host
      :if={@page && @current_scope && @navbar}
      user_id={@current_user.id}
      native
    />
    """
  end
end
