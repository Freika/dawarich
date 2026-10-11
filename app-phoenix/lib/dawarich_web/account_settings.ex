defmodule DawarichWeb.AccountSettings do
  @moduledoc false
  import Phoenix.Component
  alias Dawarich.Accounts.{Principal, Scope}
  import Phoenix.LiveView
  alias Dawarich.Accounts

  def on_mount(:default, _, _, socket) do
    with {:ok, _} <- Accounts.settings_for(socket.assigns.current_user) do
      socket =
        socket
        |> detach_principal_hooks()
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

    with %{id: _} <- user,
         true <- Dawarich.Accounts.Principal.same_identity?(original, user),
         {:ok, _} <- Accounts.settings_for(user) do
      user = Principal.project(user)

      {:cont,
       assign(socket,
         current_user: user,
         current_scope: Scope.for_user(user, socket.assigns.locale)
       )}
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

  defp detach_principal_hooks(socket) do
    Enum.reduce(
      [
        {:native_principal_event, :handle_event},
        {:native_principal_params, :handle_params},
        {:native_principal_info, :handle_info},
        {:native_principal_async, :handle_async}
      ],
      socket,
      fn {id, stage}, socket ->
        detach_hook(socket, id, stage)
      end
    )
  end

  defp before_hook(socket, id, stage, callback) do
    hooks = Map.fetch!(socket.private.lifecycle, stage)
    socket = Enum.reduce(hooks, socket, fn hook, acc -> detach_hook(acc, hook.id, stage) end)
    socket = attach_hook(socket, id, stage, callback)

    Enum.reduce(hooks, socket, fn hook, acc -> attach_hook(acc, hook.id, stage, hook.function) end)
  end
end
