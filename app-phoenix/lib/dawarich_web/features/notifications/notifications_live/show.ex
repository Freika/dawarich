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
    <div class="mx-auto md:w-2/3 w-full flex" data-testid="native-notifications-detail">
      <div :if={@notification} class="mx-auto">
        <.card notification={@notification} locale={@locale} now={@now} show_content />
        <div class="my-5">
          <a class="btn btn-small" href="/notifications">{t(
            @locale,
            "notifications.show.back_to_notifications",
            %{}
          )}</a>
          <div class="inline-block ml-2">
            <form
              class="button_to"
              method="post"
              action={"/notifications/#{@notification.id}"}
              phx-submit={
                JS.push("choose_notification_delete")
                |> JS.dispatch("dawarich:open-dialog", to: "#notification-delete-dialog")
              }
            >
              <input type="hidden" name="_method" value="delete" />
              <button type="submit" class="btn btn-small btn-warning">{t(
                @locale,
                "notifications.show.destroy_this_notification",
                %{}
              )}</button>
              <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            </form>
          </div>
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
