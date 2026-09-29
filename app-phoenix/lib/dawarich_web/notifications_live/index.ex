defmodule DawarichWeb.NotificationsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.NotificationCard, only: [card: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]

  alias Dawarich.Notifications

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(
         socket,
         :page_title,
         t(socket.assigns.locale, "notifications.index.notifications", %{})
       )}

  @impl true
  def handle_params(params, uri, socket) do
    page = max(DawarichWeb.Params.ruby_to_i(params["page"]), 1)
    query = URI.decode_query(URI.parse(uri).query || "")
    %{current_user: user, now: now} = socket.assigns

    result =
      Map.update!(
        Notifications.page(user.id, page),
        :notifications,
        &Notifications.localize(&1, user.settings, now)
      )

    {:noreply, socket |> assign(page: page, query: query) |> assign(result)}
  end

  @impl true
  def handle_event("mark_all_as_read", _params, socket) do
    Notifications.mark_all_read(socket.assigns.current_user.id)
    {:noreply, done(socket, "controllers.notifications.all_notifications_marked_as_read")}
  end

  def handle_event("destroy_all", _params, socket) do
    Notifications.delete_all(socket.assigns.current_user.id)

    {:noreply,
     done(socket, "controllers.notifications.all_notifications_where_successfully_destroyed")}
  end

  defp done(socket, key),
    do:
      socket
      |> put_flash(:notice, t(socket.assigns.locale, key, %{}))
      |> push_patch(to: "/notifications")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold">{t(@locale, "notifications.index.notifications", %{})}</h1>
        <div :if={@unread_on_page? or @notifications != []} class="flex flex-wrap gap-2">
          <a
            :if={@unread_on_page?}
            data-turbo-method="post"
            class="btn btn-sm btn-primary"
            href="/notifications/mark_as_read"
            phx-click="mark_all_as_read"
          >{t(@locale, "notifications.index.mark_all_as_read", %{})}</a>
          <a
            :if={@notifications != []}
            data-turbo-method="post"
            data-turbo-confirm={
              t(@locale, "notifications.index.are_you_sure_you_want_to_delete_all_notifications", %{})
            }
            class="btn btn-sm btn-warning"
            href="/notifications/destroy_all"
            phx-click="destroy_all"
          >{t(@locale, "notifications.index.delete_all", %{})}</a>
        </div>
      </div>
      <div class="flex justify-center mb-4">
        <.paginator
          locale={@locale}
          path="/notifications"
          query={@query}
          page={@page}
          total_pages={@total_pages}
        />
      </div>
      <div id="notifications" class="w-full max-w-2xl mx-auto">
        <.card
          :for={notification <- @notifications}
          notification={notification}
          locale={@locale}
          now={@now}
        />
      </div>
    </div>
    """
  end
end
