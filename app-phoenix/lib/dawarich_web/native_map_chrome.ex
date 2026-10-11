defmodule DawarichWeb.NativeMapChrome do
  @moduledoc false
  use DawarichWeb, :html
  import Phoenix.LiveView, only: [attach_hook: 4]

  def load(socket) do
    navbar =
      Dawarich.Maps.with_actor(socket.assigns.current_scope, fn actor ->
        Dawarich.Navbar.load(actor,
          now: socket.assigns.now,
          self_hosted: socket.assigns.self_hosted != false
        )
      end)

    socket |> assign(:navbar, navbar) |> attach_hook(:native_chrome, :handle_event, &event/3)
  end

  defp event("changelog_consent", %{"decision" => decision}, socket)
       when decision in ~w(granted declined) do
    Dawarich.Maps.with_actor(
      socket.assigns.current_scope,
      &Dawarich.Navbar.put_changelog_consent(&1, decision)
    )

    {:halt, socket}
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
