defmodule DawarichWeb.NotificationSession.Native do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]
  alias Dawarich.{Notifications, Accounts.Scope, Accounts.NativeAccess}

  def scope(socket),
    do:
      socket.assigns[:current_scope] ||
        Scope.for_user(socket.assigns.current_user, socket.assigns.locale)

  def admit(socket) do
    if socket.assigns[:notification_signed_out] or socket.redirected do
      {:error, :stale_session}
    else
      NativeAccess.admit(scope(socket))
    end
  end

  def refuse(socket) do
    socket =
      socket
      |> assign(
        notification_signed_out: true,
        current_user: nil,
        current_scope: nil,
        navbar: nil,
        notifications: [],
        notification: nil,
        entries: [],
        delete_target: nil,
        import: nil,
        record: nil,
        data: nil,
        points: nil
      )

    if socket.redirected, do: socket, else: redirect(socket, to: "/users/sign_in")
  end

  def handle_info({:domain_changed, owner, :notifications}, socket)
      when owner == socket.assigns.current_user.id do
    coalesce(owner, 100)

    case admit(socket) do
      {:ok, current} ->
        socket =
          assign(socket,
            current_scope: current,
            current_user: current.user,
            now: DateTime.utc_now()
          )

        refresh(socket, current)

      {:error, _} ->
        {:halt, refuse(socket)}
    end
  end

  def handle_info(_, socket), do: {:cont, socket}

  defp refresh(socket, current) do
    with {:ok, unread} <- Notifications.unread(current) do
      socket = assign(socket, :navbar, Map.put(socket.assigns.navbar || %{}, :unread, unread))

      cond do
        Map.has_key?(socket.assigns, :notifications) ->
          case Notifications.page(current, socket.assigns.page) do
            {:ok, page} ->
              {:halt,
               Phoenix.Component.assign(
                 socket,
                 Map.update!(page, :notifications, &localize(&1, socket))
               )}

            _ ->
              {:halt, refuse(socket)}
          end

        socket.assigns[:notification] ->
          case Notifications.get(current, socket.assigns.notification.id) do
            {:ok, notification} ->
              {:halt, assign(socket, :notification, hd(localize([notification], socket)))}

            {:error, :not_found} ->
              {:halt, socket |> assign(:notification, nil) |> redirect(to: "/notifications")}

            _ ->
              {:halt, refuse(socket)}
          end

        true ->
          {:halt, socket}
      end
    else
      _ -> {:halt, refuse(socket)}
    end
  end

  defp localize(items, socket),
    do:
      Notifications.localize(
        items,
        Dawarich.UserSettings.get(socket.assigns.current_user),
        socket.assigns.now
      )

  defp coalesce(_, 0), do: :ok

  defp coalesce(owner, left) do
    receive do
      {:domain_changed, ^owner, :notifications} -> coalesce(owner, left - 1)
    after
      0 -> :ok
    end
  end
end
