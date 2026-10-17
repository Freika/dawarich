defmodule DawarichWeb.NotificationsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Phoenix.LiveView.JS
  import DawarichWeb.NotificationCard, only: [card: 1]
  import DawarichWeb.NotificationDeleteDialog, only: [dialog: 1]
  alias Dawarich.Notifications

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Notifications.open(socket.assigns.current_scope, id) do
      {:ok, notification} ->
        [notification] =
          Notifications.localize(
            [notification],
            Dawarich.UserSettings.get(socket.assigns.current_user),
            socket.assigns.now
          )

        {:ok, assign(socket, notification: notification, delete_target: nil)}

      {:error, :not_found} ->
        if connected?(socket),
          do:
            {:ok,
             assign(socket, notification: nil, delete_target: nil)
             |> redirect(to: "/notifications")},
          else: raise(DawarichWeb.NotFoundError)

      _ ->
        {:ok, DawarichWeb.NotificationSession.Native.refuse(socket)}
    end
  end

  @impl true
  def handle_event("choose_notification_delete", _, socket),
    do: {:noreply, assign(socket, :delete_target, socket.assigns.notification.id)}

  def handle_event("cancel_notification_delete", _, socket),
    do: {:noreply, assign(socket, :delete_target, nil)}

  def handle_event("confirm_notification_delete", _, %{assigns: %{delete_target: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm_notification_delete", _, socket) do
    id = socket.assigns.delete_target
    socket = assign(socket, :delete_target, nil)

    case Notifications.delete(socket.assigns.current_scope, id) do
      {:ok, :deleted} ->
        {:noreply,
         socket
         |> assign(:notification, nil)
         |> put_flash(
           :notice,
           t(
             socket.assigns.locale,
             "controllers.notifications.notification_was_successfully_destroyed",
             %{}
           )
         )
         |> redirect(to: "/notifications")}

      {:error, :not_found} ->
        {:noreply, socket |> assign(:notification, nil) |> redirect(to: "/notifications")}

      _ ->
        {:noreply, DawarichWeb.NotificationSession.Native.refuse(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto md:w-2/3 w-full min-w-0" data-testid="native-notifications-detail">
      <div :if={@notification} class="mx-auto min-w-0">
        <.card notification={@notification} locale={@locale} now={@now} show_content />
        <div class="my-5 flex flex-wrap gap-2 min-w-0">
          <a class="btn btn-small h-auto whitespace-normal" href="/notifications">{t(
            @locale,
            "notifications.show.back_to_notifications",
            %{}
          )}</a>
          <button
            type="button"
            class="btn btn-small btn-warning h-auto whitespace-normal"
            phx-click={
              JS.push("choose_notification_delete")
              |> JS.dispatch("dawarich:open-dialog", to: "#notification-delete-dialog")
            }
          >{t(@locale, "notifications.show.destroy_this_notification", %{})}</button>
        </div>
      </div>
      <.dialog
        locale={@locale}
        target={@delete_target}
        id="notification-delete-dialog"
        title_id="notification-delete-title"
        title={t(@locale, "notifications.show.are_you_sure", %{})}
        cancel="cancel_notification_delete"
        confirm="confirm_notification_delete"
      />
    </div>
    """
  end
end
