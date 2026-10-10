defmodule DawarichWeb.PlacesLiveAuth do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4, detach_hook: 3]
  alias Dawarich.Places.Access
  alias Dawarich.Accounts.Principal
  alias DawarichWeb.{PlacesUI, PlacesActor}

  def on_mount(:default, _, _, socket) do
    actor = socket.assigns.current_scope.user

    origin = Principal.scope(socket.assigns.current_scope)

    layout_actor = PlacesActor.project(actor)

    socket =
      socket
      |> assign(
        current_user: layout_actor,
        current_scope: %{socket.assigns.current_scope | user: layout_actor}
      )
      |> scrub_actor_changes()
      |> assign(:places_origin, origin)
      |> detach_hook(:rails_user, :handle_event)
      |> before_hook(:places_event, :handle_event, fn _, _, socket -> authorize(socket) end)
      |> before_hook(:places_params, :handle_params, fn _, _, socket -> authorize(socket) end)
      |> before_hook(:places_info, :handle_info, fn _, socket -> authorize(socket) end)
      |> before_hook(:places_async, :handle_async, fn _, _, socket -> authorize(socket) end)

    case authorize(socket) do
      {:halt, %{redirected: nil} = refused} -> {:cont, refused}
      result -> result
    end
  end

  defp scrub_actor_changes(socket) do
    changed = Map.merge(socket.assigns.__changed__, %{current_user: true, current_scope: true})
    %{socket | assigns: %{socket.assigns | __changed__: changed}}
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
      {:ok, scope} ->
        actor = PlacesActor.project(scope.user)
        {:cont, assign(socket, current_scope: %{scope | user: actor}, current_user: actor)}

      {:error, reason} ->
        {:halt, PlacesUI.refuse(socket, reason)}
    end
  end
end
