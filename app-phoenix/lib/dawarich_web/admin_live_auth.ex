defmodule DawarichWeb.AdminLiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias Dawarich.Accounts
  alias DawarichWeb.{AdminGate, LayoutAssigns, LiveAuth}

  def on_mount(mode, params, session, socket) when mode in [:admin, :background] do
    socket =
      socket
      |> assign(:admin_mode, mode)
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

  defp authorize(socket) do
    actor = socket.assigns.current_user
    user = actor && Accounts.get(actor.id)

    if LayoutAssigns.self_hosted?() and not is_nil(user) and
         (socket.assigns.admin_mode == :background or user.admin == true) and
         AdminGate.supported?(user) do
      {:cont, assign(socket, :current_user, user)}
    else
      {:halt, redirect(socket, to: request_url(socket))}
    end
  end

  def request_url(socket) do
    query = socket.assigns.query_params || %{}
    socket.assigns.request_path <> if(query == %{}, do: "", else: "?" <> URI.encode_query(query))
  end
end
