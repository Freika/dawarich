defmodule DawarichWeb.PlacesLiveAuth do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4, detach_hook: 3]
  alias Dawarich.Places.Access
  alias Dawarich.Accounts.{Scope, User}
  alias DawarichWeb.PlacesUI

  def on_mount(:default, _, _, socket) do
    actor = socket.assigns.current_scope.user

    origin =
      Scope.for_user(
        struct(User, Map.take(actor, [:id, :encrypted_password])),
        socket.assigns.locale
      )

    socket =
      socket
      |> assign(:places_origin, origin)
      |> detach_hook(:rails_user, :handle_event)
      |> before_hook(:places_event, :handle_event, fn _, _, socket -> authorize(socket) end)
      |> before_hook(:places_params, :handle_params, fn _, _, socket -> authorize(socket) end)
      |> before_hook(:places_info, :handle_info, fn _, socket -> authorize(socket) end)
      |> before_hook(:places_async, :handle_async, fn _, _, socket -> authorize(socket) end)

    authorize(socket)
  end

  defp before_hook(socket, id, stage, callback) do
    hooks = Map.fetch!(socket.private.lifecycle, stage)
    socket = Enum.reduce(hooks, socket, fn hook, acc -> detach_hook(acc, hook.id, stage) end)
    socket = attach_hook(socket, id, stage, callback)

    Enum.reduce(hooks, socket, fn hook, acc -> attach_hook(acc, hook.id, stage, hook.function) end)
  end

  def authorize(%{redirected: redirected} = socket) when not is_nil(redirected),
    do: {:halt, socket}

  def authorize(socket) do
    case Access.admit(socket.assigns.places_origin) do
      {:ok, scope} -> {:cont, assign(socket, current_scope: scope, current_user: scope.user)}
      {:error, reason} -> {:halt, PlacesUI.refuse(socket, reason)}
    end
  end
end
