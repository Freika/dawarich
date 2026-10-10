defmodule DawarichWeb.MapLiveAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]
  alias Dawarich.Accounts.Scope
  alias Dawarich.Maps

  @layout ~w(locale suggested_locale self_hosted request_path query_params base_url notification_session)a

  def live_session(conn) do
    session = DawarichWeb.RailsAuth.live_session(conn)
    user = conn.assigns[:current_user]
    Map.put(session, "map_identity", user && Dawarich.Maps.Dependencies.Principal.identity(user))
  end

  def on_mount(:default, _params, session, socket) do
    connected_id =
      if connected?(socket),
        do: (get_connect_info(socket, :session) || %{})["rails_user_id"],
        else: session["rails_user_id"]

    scope = %Scope{
      user: %{id: session["rails_user_id"], session_identity: session["map_identity"]},
      locale: session["locale"]
    }

    socket =
      socket
      |> assign(for key <- @layout, do: {key, session[Atom.to_string(key)]})
      |> assign(
        current_scope: scope,
        current_user: nil,
        page: nil,
        map_error: nil,
        native: true,
        now: DateTime.utc_now(),
        navbar: nil,
        page_title: nil,
        flash_messages: []
      )

    if connected_id == session["rails_user_id"] do
      socket
      |> attach_hook(:map_admission_event, :handle_event, fn _, _, s -> authorize(s) end)
      |> attach_hook(:map_admission_params, :handle_params, fn _, _, s -> authorize(s) end)
      |> attach_hook(:map_admission_info, :handle_info, fn _, s -> authorize(s) end)
      |> attach_hook(:map_admission_async, :handle_async, fn _, _, s -> authorize(s) end)
      |> authorize()
      |> then(fn
        {:halt, %{redirected: nil} = refused} -> {:cont, refused}
        result -> result
      end)
    else
      {:halt, refuse(socket, :stale_session)}
    end
  end

  def authorize(%{assigns: %{current_scope: nil, map_error: reason}} = socket)
      when not is_nil(reason),
      do: {:halt, socket}

  def authorize(socket) do
    case Maps.admit(socket.assigns.current_scope) do
      {:ok, scope} ->
        {:cont,
         assign(socket, current_scope: scope, current_user: scope.user, now: DateTime.utc_now())}

      {:error, reason} ->
        {:halt, refuse(socket, reason)}
    end
  end

  def refuse(socket, reason) do
    socket = DawarichWeb.MapLive.Subscriptions.release(socket)
    socket = assign(socket, page: nil, current_user: nil, current_scope: nil, map_error: reason)
    if reason == :stale_session, do: redirect(socket, to: "/users/sign_in"), else: socket
  end
end
