defmodule DawarichWeb.NativeAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias Dawarich.Accounts.Scope

  def live_session(conn) do
    session = DawarichWeb.RailsAuth.live_session(conn)

    if conn.request_path == "/tags/new",
      do: Map.put(session, "tag_default_emoji", DawarichWeb.TagEmoji.random()),
      else: session
  end

  def on_mount(:require_user, params, session, socket) do
    case DawarichWeb.LiveAuth.on_mount(:default, params, session, socket) do
      {:cont, %{assigns: %{current_user: nil}} = socket} ->
        {:halt, redirect(socket, to: "/users/sign_in")}

      {:cont, socket} ->
        scope = Scope.for_user(socket.assigns.current_user, socket.assigns.locale)
        {:cont, socket |> assign(:current_scope, scope) |> assign(:native, true)}

      halt ->
        halt
    end
  end
end
