defmodule DawarichWeb.NotificationsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.NotificationCard, only: [card: 1]

  alias Dawarich.Notifications

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_user.id

    case Notifications.get(user_id, DawarichWeb.Params.ruby_to_i(id)) do
      nil ->
        raise DawarichWeb.NotFoundError

      notification ->
        {:ok, assign(socket, :notification, Notifications.mark_read(user_id, notification))}
    end
  end

  @impl true
  def handle_event("destroy", _params, socket) do
    Notifications.delete(socket.assigns.current_user.id, socket.assigns.notification.id)

    message =
      t(
        socket.assigns.locale,
        "controllers.notifications.notification_was_successfully_destroyed",
        %{}
      )

    {:noreply, socket |> put_flash(:notice, message) |> redirect(to: "/notifications")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto md:w-2/3 w-full flex">
      <div class="mx-auto">
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
              phx-submit="destroy"
            >
              <input type="hidden" name="_method" value="delete" /><button
                data-turbo-confirm={t(@locale, "notifications.show.are_you_sure", %{})}
                class="btn btn-small btn-warning"
                type="submit"
              >{t(@locale, "notifications.show.destroy_this_notification", %{})}</button><input
                :if={@rails_csrf_token}
                type="hidden"
                name="authenticity_token"
                value={@rails_csrf_token}
              />
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
