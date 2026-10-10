defmodule DawarichWeb.NativeFamilyAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]
  alias Dawarich.Accounts.{NativeAccess, Principal, Scope}
  alias DawarichWeb.{LayoutAssigns, LiveAuth, NativeJobsAuth}

  def live_session(conn), do: NativeJobsAuth.live_session(conn)

  def on_mount(:require_user, params, session, socket) do
    socket =
      socket
      |> attach_hook(:native_family_params, :handle_params, fn _, uri, socket ->
        authorize(track(socket, uri))
      end)
      |> attach_hook(:native_family_event, :handle_event, fn _, _, socket -> authorize(socket) end)
      |> attach_hook(:native_family_info, :handle_info, fn _, socket -> authorize(socket) end)
      |> attach_hook(:native_family_async, :handle_async, fn _, _, socket -> authorize(socket) end)

    with {:cont, socket} <- LiveAuth.on_mount(:default, params, session, socket),
         true <-
           Principal.same_identity?(
             %{session_version: session["native_identity"]},
             socket.assigns.current_user
           ) do
      user = Principal.project(socket.assigns.current_user)

      socket
      |> assign(
        current_user: user,
        current_scope: Scope.for_user(user, socket.assigns.locale),
        native: true
      )
      |> authorize()
    else
      {:halt, socket} -> {:halt, socket}
      _ -> {:halt, refuse(socket, "/users/sign_in")}
    end
  end

  def authorize(%{redirected: redirected} = socket) when not is_nil(redirected),
    do: {:halt, socket}

  def authorize(socket) do
    now = DateTime.utc_now()
    hosted = Dawarich.ReleaseMigration.self_hosted?()

    with {:ok, scope} <- NativeAccess.admit(socket.assigns[:current_scope]),
         {:ok, action} <- action(socket.assigns.request_path),
         {:ok, page} <- Dawarich.Families.page(scope, action, now: now, self_hosted: hosted) do
      {:cont,
       assign(socket,
         current_user: scope.user,
         current_scope: scope,
         now: now,
         self_hosted: hosted,
         family_action: action,
         page: page,
         navbar: indicator(socket.assigns[:navbar], page),
         native: true,
         rails_js: false
       )}
    else
      {:error, :stale_session} -> {:halt, refuse(socket, "/users/sign_in")}
      {:error, _} -> {:halt, refuse(socket, destination(socket.assigns.request_path))}
    end
  end

  defp indicator(%{family: family} = navbar, page) do
    sharing = get_in(page, [:me, :sharing, :enabled?]) == true and page.state != :lapsed
    %{navbar | family: %{family | sharing: sharing}}
  end

  defp indicator(navbar, _), do: navbar

  def action("/family"), do: {:ok, :show}
  def action("/family/new"), do: {:ok, :new}
  def action("/family/edit"), do: {:ok, :edit}
  def action("/family/invitations"), do: {:ok, :invitations}

  def action("/family/location_requests/" <> id) when byte_size(id) <= 19 do
    case Integer.parse(id) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, {:request, id}}
      _ -> {:error, :invalid_input}
    end
  end

  def action(_), do: {:error, :invalid_input}

  defp destination("/family/new"), do: "/family"
  defp destination("/family/edit"), do: "/"
  defp destination("/family/location_requests/" <> _), do: "/family"
  defp destination(_), do: "/family/new"

  defp refuse(socket, path) do
    socket
    |> assign(
      page: nil,
      locations: [],
      history: nil,
      confirmation: nil,
      current_user: nil,
      current_scope: nil,
      navbar: nil
    )
    |> redirect(to: if(path == socket.assigns[:request_path], do: "/", else: path))
  end

  defp track(socket, uri) do
    %URI{path: path, query: query} = URI.parse(uri)

    assign(socket,
      request_path: LayoutAssigns.safe_path(path),
      query_params: Plug.Conn.Query.decode(query || "")
    )
  end
end
