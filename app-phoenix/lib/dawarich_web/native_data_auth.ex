defmodule DawarichWeb.NativeDataAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, detach_hook: 3, put_flash: 3, redirect: 2]
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.NativeM5.Dependencies
  alias DawarichWeb.{DataAsync, NativeAuth, Translate}

  def on_mount(:require_user, params, session, socket) do
    socket =
      socket
      |> attach_hook(:data_params, :handle_params, fn _, _, socket ->
        authorize(socket, :params)
      end)
      |> attach_hook(:data_event, :handle_event, fn _, _, socket -> authorize(socket, :event) end)
      |> attach_hook(:data_info, :handle_info, &info/2)
      |> attach_hook(:data_async, :handle_async, fn _, _, socket -> authorize(socket, :async) end)

    with {:cont, socket} <- NativeAuth.on_mount(:require_user, params, session, socket) do
      principal = Dependencies.principal(socket.assigns.current_scope)
      socket = %{socket | private: Map.put(socket.private, :data_principal, principal)}

      socket
      |> detach_hook(:rails_user, :handle_event)
      |> detach_hook(:notification_session, :handle_event)
      |> authorize(:mount)
    end
  end

  defp info(:notification_signed_out, socket), do: {:halt, refuse(socket, :stale_session)}
  defp info(_, socket), do: authorize(socket, :info)

  def scope(socket), do: DataAccess.admit(socket.private[:data_principal])

  def authorize(socket, _boundary) do
    case scope(socket) do
      {:ok, scope} ->
        socket = assign(socket, :current_user, redact(scope.user))

        changed =
          socket.assigns.__changed__ |> Map.delete(:current_scope) |> Map.put(:current_user, true)

        assigns = socket.assigns |> Map.delete(:current_scope) |> Map.put(:__changed__, changed)
        {:cont, %{socket | assigns: assigns}}

      {:error, reason} ->
        {:halt, refuse(socket, reason)}
    end
  end

  def refuse(socket, :stale_session, _destination) do
    socket = DataAsync.cancel_all(socket)
    assigns = Map.take(socket.assigns, [:__changed__, :locale, :flash])
    socket = %{socket | assigns: assigns, private: Map.delete(socket.private, :data_principal)}
    redirect(socket, to: "/users/sign_in")
  end

  def refuse(socket, reason, destination) when reason in [:not_found, :unauthorized] do
    socket
    |> alert()
    |> redirect(to: destination)
  end

  def refuse(socket, _reason, _destination), do: alert(socket)
  def refuse(socket, reason), do: refuse(socket, reason, "/")

  defp alert(socket),
    do:
      put_flash(
        socket,
        :alert,
        Translate.t(
          socket.assigns[:locale] || "en",
          "controllers.application.admin_action_failed",
          %{}
        )
      )

  defp redact(user), do: %{user | encrypted_password: nil, api_key: nil, settings: %{}}
end
