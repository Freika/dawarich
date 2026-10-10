defmodule DawarichWeb.NativeJobsAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]
  alias Dawarich.Accounts.{NativeAccess, Principal, Scope}
  alias DawarichWeb.{LayoutAssigns, LiveAuth, NativeAuth}

  def live_session(conn) do
    NativeAuth.live_session(conn)
    |> Map.put("native_identity", Principal.version(conn.assigns[:current_user]))
  end

  def on_mount(:require_user, params, session, socket) do
    socket =
      socket
      |> attach_hook(:native_jobs_params, :handle_params, fn _params, uri, socket ->
        socket |> track(uri) |> authorize()
      end)
      |> attach_hook(:native_jobs_event, :handle_event, fn _event, _params, socket ->
        authorize(socket)
      end)
      |> attach_hook(:native_jobs_info, :handle_info, fn _message, socket -> authorize(socket) end)
      |> attach_hook(:native_jobs_async, :handle_async, fn _name, _result, socket ->
        authorize(socket)
      end)

    with {:cont, socket} <- LiveAuth.on_mount(:default, params, session, socket),
         true <-
           Principal.same_identity?(
             %{session_version: session["native_identity"]},
             socket.assigns.current_user
           ) do
      authorize(
        assign(
          socket,
          :current_scope,
          Scope.for_user(socket.assigns.current_user, socket.assigns.locale)
        )
      )
    else
      {:halt, socket} -> {:halt, socket}
      _ -> {:halt, refuse(socket)}
    end
  end

  def authorize(%{redirected: redirected} = socket) when not is_nil(redirected),
    do: {:halt, socket}

  def authorize(socket) do
    case NativeAccess.admit(socket.assigns[:current_scope]) do
      {:ok, scope} ->
        {:cont, assign(socket, current_user: scope.user, current_scope: scope, native: true)}

      {:error, _} ->
        {:halt, refuse(socket)}
    end
  end

  defp refuse(socket) do
    socket
    |> assign(
      current_user: nil,
      current_scope: nil,
      navbar: nil,
      entries: [],
      delete_target: nil,
      notifications: [],
      notification: nil,
      data: nil,
      import: nil,
      record: nil,
      points: nil
    )
    |> redirect(to: "/users/sign_in")
  end

  defp track(socket, uri) do
    %URI{path: path, query: query} = URI.parse(uri)

    assign(socket,
      request_path: LayoutAssigns.safe_path(path),
      query_params: Plug.Conn.Query.decode(query || "")
    )
  end
end
