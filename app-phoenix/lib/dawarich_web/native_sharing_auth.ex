defmodule DawarichWeb.NativeSharingAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2, push_event: 3]
  alias Dawarich.Accounts.{NativeAccess, Principal, Scope}
  alias DawarichWeb.{LayoutAssigns, LiveAuth, NativeJobsAuth, SharingResource}
  def live_session(conn), do: NativeJobsAuth.live_session(conn)

  def on_mount(:require_user, params, session, socket) do
    socket =
      socket
      |> attach_hook(:sharing_params, :handle_params, fn p, uri, s ->
        authorize(track(s, p, uri))
      end)
      |> attach_hook(:sharing_event, :handle_event, fn _, _, s -> authorize(s) end)
      |> attach_hook(:sharing_info, :handle_info, fn _, s -> authorize(s) end)
      |> attach_hook(:sharing_async, :handle_async, fn _, _, s -> authorize(s) end)

    with {:cont, socket} <- LiveAuth.on_mount(:default, params, session, socket),
         true <-
           Principal.same_identity?(
             %{session_version: session["native_identity"]},
             socket.assigns.current_user
           ) do
      socket =
        assign(socket,
          current_scope:
            Scope.for_user(Principal.project(socket.assigns.current_user), socket.assigns.locale),
          native: true
        )

      if connected?(socket), do: Dawarich.Sharing.subscribe(socket.assigns.current_scope)
      authorize(socket)
    else
      {:halt, socket} -> {:halt, socket}
      _ -> {:halt, refuse(socket, "/users/sign_in")}
    end
  end

  def authorize(%{redirected: redirected} = socket) when not is_nil(redirected),
    do: {:halt, socket}

  def authorize(socket) do
    with {:ok, scope} <- NativeAccess.admit(socket.assigns[:current_scope]),
         {:ok, base, tab} <-
           SharingResource.from(
             socket.assigns.request_path,
             scope.user.id,
             socket.assigns.query_params || %{}
           ),
         {:ok, page} <- Dawarich.Sharing.page(scope, base, socket.assigns.query_params || %{}) do
      {:cont,
       assign(socket,
         current_scope: scope,
         current_user: scope.user,
         resource: SharingResource.selected(base, if(base.type == :hub, do: page.tab, else: tab)),
         base_resource: base,
         page: page,
         tab: if(base.type == :hub, do: page.tab, else: tab),
         native: true,
         rails_js: false
       )}
    else
      {:error, :stale_session} -> {:halt, refuse(socket, "/users/sign_in")}
      _ -> {:halt, refuse(socket, "/map/v2")}
    end
  end

  defp refuse(socket, path) do
    socket
    |> assign(
      current_scope: nil,
      current_user: nil,
      page: nil,
      resource: nil,
      base_resource: nil,
      form_values: %{},
      confirmation: nil,
      navbar: nil
    )
    |> push_event("sharing-clear", %{})
    |> redirect(to: path)
  end

  defp track(socket, params, uri) do
    assign(socket,
      request_path: LayoutAssigns.safe_path(URI.parse(uri).path),
      query_params: params,
      confirmation: nil,
      form_values: %{}
    )
  end
end
