defmodule DawarichWeb.NotificationSession do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2]
  alias Dawarich.{Accounts, Cable.Bus, Notifications}

  def topic(session) do
    case {session["warden.user.user.key"], session["_csrf_token"] || session["session_id"]} do
      {[[id], _], value} when is_integer(id) and is_binary(value) ->
        "notification-session:" <>
          Base.encode16(:crypto.hash(:sha256, "#{id}:" <> value), case: :lower)

      _ ->
        nil
    end
  end

  def signed_out(session) do
    if topic = topic(session),
      do: Phoenix.PubSub.broadcast(Dawarich.PubSub, topic, :notification_signed_out)

    :ok
  end

  def attach(socket) do
    if connected?(socket) do
      if topic = socket.assigns[:notification_session],
        do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic)

      if Process.whereis(Bus), do: Bus.subscribe(stream(socket))
    end

    socket
    |> assign(:notification_signed_out, false)
    |> attach_hook(:notification_session, :handle_event, &authorize/3)
    |> attach_hook(:notification_publication, :handle_info, &info/2)
  end

  defp authorize(_event, _params, socket) do
    actor = socket.assigns.current_user
    fresh = actor && Accounts.get(actor.id)

    if socket.assigns.notification_signed_out or is_nil(fresh) or
         fresh.encrypted_password != actor.encrypted_password,
       do: {:halt, redirect(socket, to: "/users/sign_in")},
       else: {:cont, socket}
  end

  defp info(:notification_signed_out, socket),
    do: {:halt, assign(socket, :notification_signed_out, true)}

  defp info(message, socket) do
    case Bus.event(message) do
      {:subscribed, channel} ->
        if channel == stream(socket), do: {:halt, socket}, else: {:cont, socket}

      {:message, channel, _payload} ->
        if channel == stream(socket), do: {:halt, refresh(socket)}, else: {:cont, socket}

      _ ->
        {:cont, socket}
    end
  end

  defp stream(socket),
    do:
      Dawarich.RailsMessages.broadcasting([
        {:user, socket.assigns.current_user.id},
        "notifications"
      ])

  defp refresh(socket) do
    id = socket.assigns.current_user.id

    socket =
      assign(socket, :navbar, Map.put(socket.assigns.navbar, :unread, Dawarich.Navbar.unread(id)))

    cond do
      Map.has_key?(socket.assigns, :notifications) ->
        result = Notifications.page(id, socket.assigns.page)

        result =
          Map.update!(
            result,
            :notifications,
            &Notifications.localize(
              &1,
              Dawarich.UserSettings.get(socket.assigns.current_user),
              socket.assigns.now
            )
          )

        Phoenix.Component.assign(socket, result)

      Map.has_key?(socket.assigns, :notification) ->
        case Notifications.get(id, socket.assigns.notification.id) do
          nil ->
            socket

          notification ->
            [notification] =
              Notifications.localize(
                [notification],
                Dawarich.UserSettings.get(socket.assigns.current_user),
                socket.assigns.now
              )

            assign(socket, :notification, notification)
        end

      true ->
        socket
    end
  end
end
