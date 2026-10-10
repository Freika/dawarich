defmodule DawarichWeb.NativeAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias Dawarich.Accounts.Scope

  def live_session(conn) do
    session = DawarichWeb.RailsAuth.live_session(conn)

    case conn.request_path do
      "/tags/new" -> Map.put(session, "tag_default_emoji", DawarichWeb.TagEmoji.random())
      "/users/edit" -> Map.put(session, "account_form", conn.assigns[:account_form])
      _ -> session
    end
  end

  def on_mount(:require_user, params, session, socket) do
    socket =
      socket
      |> assign(:native, true)
      |> attach_hook(:native_principal_params, :handle_params, fn _, _, socket ->
        DawarichWeb.NativeJobsAuth.authorize(socket)
      end)
      |> attach_hook(:native_principal_event, :handle_event, fn _, _, socket ->
        DawarichWeb.NativeJobsAuth.authorize(socket)
      end)
      |> attach_hook(:native_principal_info, :handle_info, fn _, socket ->
        DawarichWeb.NativeJobsAuth.authorize(socket)
      end)
      |> attach_hook(:native_principal_async, :handle_async, fn _, _, socket ->
        DawarichWeb.NativeJobsAuth.authorize(socket)
      end)

    case DawarichWeb.LiveAuth.on_mount(:default, params, session, socket) do
      {:cont, %{assigns: %{current_user: nil}} = socket} ->
        {:halt, redirect(socket, to: "/users/sign_in")}

      {:cont, socket} ->
        user = Dawarich.Accounts.Principal.project(socket.assigns.current_user)
        scope = Scope.for_user(user, socket.assigns.locale)

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_scope, scope)
         |> assign(:native, true)
         |> attach_hook(:native_request_path, :handle_params, &track_uri/3)}

      halt ->
        halt
    end
  end

  defp track_uri(_params, uri, socket),
    do:
      {:cont,
       assign(socket, :request_path, DawarichWeb.LayoutAssigns.safe_path(URI.parse(uri).path))}
end
