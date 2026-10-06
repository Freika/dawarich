defmodule DawarichWeb.AdminLiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2, connected?: 1, get_connect_info: 2]

  alias Dawarich.Accounts
  alias DawarichWeb.{AdminGate, LayoutAssigns, LiveAuth, OperatorGrant, OperatorRedirect}

  def on_mount(mode, params, session, socket) when mode in [:admin, :background] do
    socket =
      socket
      |> assign(:admin_mode, mode)
      |> assign(:operator_context, operator_context(session, socket))
      |> attach_hook(:admin_role_event, :handle_event, fn _event, _params, socket ->
        authorize(socket)
      end)
      |> attach_hook(:admin_role_params, :handle_params, fn _params, _uri, socket ->
        authorize(socket)
      end)
      |> attach_hook(:admin_role_info, :handle_info, fn _message, socket -> authorize(socket) end)

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

    if hosting and not is_nil(user) and current_identity?(actor, user) and
         (socket.assigns.admin_mode == :background or user.admin == true) and
         AdminGate.supported?(user) do
      socket = assign(socket, :current_user, user)
      socket = if user.admin == true, do: socket, else: assign(socket, :health, nil)
      {:cont, socket}
    else
      {:halt,
       socket
       |> assign(:current_user, user)
       |> assign(:health, nil)
       |> redirect(to: request_url(socket))}
    end
  end

  defp current_identity?(%{encrypted_password: original}, %{encrypted_password: current})
       when is_binary(original) and is_binary(current),
       do: Plug.Crypto.secure_compare(String.slice(original, 0, 29), String.slice(current, 0, 29))

  defp current_identity?(_, _), do: false

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
