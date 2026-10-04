defmodule DawarichWeb.TrialLiveAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]
  alias Dawarich.Accounts
  alias DawarichWeb.LiveAuth

  def on_mount(:default, params, session, socket) do
    socket =
      socket
      |> attach_hook(:trial_status_event, :handle_event, fn _event, _params, socket ->
        authorize(socket)
      end)
      |> attach_hook(:trial_status_info, :handle_info, fn _message, socket ->
        authorize(socket)
      end)

    case LiveAuth.on_mount(:default, params, session, socket) do
      {:cont, socket} -> authorize(socket)
      halted -> halted
    end
  end

  defp authorize(socket) do
    actor = socket.assigns.current_user
    user = actor && Accounts.get(actor.id)

    if user && user.status == 3 do
      {:cont, assign(socket, :current_user, user)}
    else
      {:halt, redirect(socket, to: socket.assigns.request_path)}
    end
  end
end
