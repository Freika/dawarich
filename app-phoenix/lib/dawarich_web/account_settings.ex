defmodule DawarichWeb.AccountSettings do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView
  alias Dawarich.Accounts

  def on_mount(:default, _, _, socket) do
    with {:ok, _} <- Accounts.settings_for(socket.assigns.current_user) do
      socket =
        socket
        |> before_hook(:account_settings_event, :handle_event, fn _, _, s -> authorize(s) end)
        |> before_hook(:account_settings_params, :handle_params, fn _, _, s -> authorize(s) end)
        |> before_hook(:account_settings_info, :handle_info, fn _, s -> authorize(s) end)
        |> before_hook(:account_settings_async, :handle_async, fn _, _, s -> authorize(s) end)

      {:cont, socket}
    else
      {:error, _} -> {:halt, refuse(socket)}
    end
  end

  def authorize(socket) do
    original = socket.assigns.current_user
    user = Accounts.get(original.id)

    with %{encrypted_password: password} <- user,
         true <- password == original.encrypted_password,
         {:ok, _} <- Accounts.settings_for(user) do
      {:cont, socket}
    else
      {:error, _} -> {:halt, refuse(socket)}
      _ -> {:halt, redirect(socket, to: "/users/sign_in")}
    end
  end

  def refuse(socket) do
    socket
    |> assign(
      form: nil,
      view: nil,
      sources: [],
      current_scope: nil,
      current_user: nil,
      navbar: nil
    )
    |> put_flash(
      :alert,
      DawarichWeb.Translate.t(
        socket.assigns.locale,
        "controllers.application.admin_action_failed",
        %{}
      )
    )
    |> redirect(to: "/")
  end

  defp before_hook(socket, id, stage, callback) do
    hooks = Map.fetch!(socket.private.lifecycle, stage)
    socket = Enum.reduce(hooks, socket, fn hook, acc -> detach_hook(acc, hook.id, stage) end)
    socket = attach_hook(socket, id, stage, callback)

    Enum.reduce(hooks, socket, fn hook, acc -> attach_hook(acc, hook.id, stage, hook.function) end)
  end
end
