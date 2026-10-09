defmodule DawarichWeb.AdminLiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [attach_hook: 4, redirect: 2, connected?: 1, get_connect_info: 2, put_flash: 3]

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope

  alias DawarichWeb.{
    AdminGate,
    LayoutAssigns,
    LiveAuth,
    OperatorGrant,
    OperatorRedirect,
    Translate
  }

  def on_mount(:native_admin, params, session, socket),
    do: on_mount(:admin, params, session, assign(socket, :native, true))

  def on_mount(:native_background, params, session, socket),
    do: on_mount(:background, params, session, assign(socket, :native, true))

  def on_mount(mode, params, session, socket) when mode in [:admin, :background] do
    socket =
      socket
      |> assign(:admin_mode, mode)
      |> assign(:operator_context, operator_context(session, socket))
      |> attach_hook(:admin_role_event, :handle_event, fn _event, _params, socket ->
        authorize(socket)
      end)
      |> attach_hook(:admin_role_params, :handle_params, fn _params, uri, socket ->
        socket |> track_uri(uri) |> authorize()
      end)
      |> attach_hook(:admin_role_info, :handle_info, fn _message, socket -> authorize(socket) end)
      |> attach_hook(:admin_role_async, :handle_async, fn _name, _result, socket ->
        authorize(socket)
      end)

    case LiveAuth.on_mount(:default, params, session, socket) do
      {:cont, socket} -> authorize(socket)
      halted -> halted
    end
  end

  def authorize(%{redirected: redirected} = socket) when not is_nil(redirected),
    do: {:halt, socket}

  def authorize(socket) do
    actor = socket.assigns.current_user
    user = actor && Accounts.get(actor.id)

    hosting =
      LayoutAssigns.self_hosted?() or
        (socket.assigns.admin_mode == :background and
           operator_authorized?(user, socket))

    refusal =
      cond do
        is_nil(user) or not current_identity?(actor, user) -> :stale_session
        not hosting and socket.assigns.admin_mode == :background -> :operator
        not hosting -> :unauthorized
        socket.assigns.admin_mode == :admin and user.admin != true -> :unauthorized
        not AdminGate.supported?(user) -> :unsupported
        true -> nil
      end

    if is_nil(refusal) do
      socket =
        socket
        |> assign(:current_user, user)
        |> assign(:current_scope, Scope.for_user(user, socket.assigns[:locale]))

      socket = if user.admin == true, do: socket, else: assign(socket, :health, nil)
      {:cont, socket}
    else
      {:halt,
       socket
       |> assign(:current_user, user)
       |> assign(:health, nil)
       |> refuse(refusal)}
    end
  end

  defp refuse(socket, :stale_session), do: redirect(socket, to: "/users/sign_in")
  defp refuse(socket, :unsupported), do: redirect(socket, to: "/settings/general")
  defp refuse(socket, :operator), do: redirect(socket, to: request_url(socket))

  defp refuse(socket, :unauthorized),
    do:
      socket
      |> put_flash(
        :alert,
        Translate.t(
          socket.assigns[:locale] || "en",
          "controllers.application.you_are_not_authorized_to_perform_this_action",
          %{}
        )
      )
      |> redirect(to: "/")

  defp track_uri(socket, uri) do
    %URI{path: path, query: query} = URI.parse(uri)

    socket
    |> assign(:request_path, LayoutAssigns.safe_path(path))
    |> assign(:query_params, if(query, do: URI.decode_query(query), else: %{}))
  end

  defp current_identity?(original, current),
    do: Dawarich.Admin.Access.same_identity?(original, current)

  defp operator_context(session, socket) do
    if connected?(socket),
      do: get_connect_info(socket, :session) || %{},
      else: session["operator_authorized"] == true
  end

  defp operator_authorized?(user, socket) do
    if connected?(socket),
      do: OperatorGrant.authorized?(user, socket.assigns.operator_context),
      else: OperatorRedirect.operator?(user) and socket.assigns.operator_context == true
  end

  def request_url(socket) do
    query = socket.assigns.query_params || %{}
    socket.assigns.request_path <> if(query == %{}, do: "", else: "?" <> URI.encode_query(query))
  end
end
