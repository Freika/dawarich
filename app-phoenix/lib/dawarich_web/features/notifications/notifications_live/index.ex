defmodule DawarichWeb.NotificationsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Phoenix.LiveView.JS
  import DawarichWeb.NotificationCard, only: [card: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  import DawarichWeb.NotificationDeleteDialog, only: [dialog: 1]
  alias Dawarich.Notifications

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket,
         page_title: t(socket.assigns.locale, "notifications.index.notifications", %{}),
         delete_target: nil
       )}

  @impl true
  def handle_params(params, uri, socket) do
    page = max(DawarichWeb.Params.ruby_to_i(params["page"]), 1)
    query = URI.decode_query(URI.parse(uri).query || "")
    {:noreply, socket |> assign(page: page, query: query) |> refresh()}
  end

  @impl true
  def handle_event("mark_all_as_read", _, socket) do
    case Notifications.mark_all_read(socket.assigns.current_scope) do
      {:ok, _} ->
        {:noreply, done(socket, "controllers.notifications.all_notifications_marked_as_read")}

      _ ->
        {:noreply, DawarichWeb.NotificationSession.Native.refuse(socket)}
    end
  end

  def handle_event("choose_notifications_delete_all", _, socket),
    do: {:noreply, assign(socket, :delete_target, :all)}

  def handle_event("cancel_notifications_delete_all", _, socket),
    do: {:noreply, assign(socket, :delete_target, nil)}

  def handle_event(
        "confirm_notifications_delete_all",
        _,
        %{assigns: %{delete_target: nil}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("confirm_notifications_delete_all", _, socket) do
    socket = assign(socket, :delete_target, nil)

    case Notifications.delete_all(socket.assigns.current_scope) do
      {:ok, _} ->
        {:noreply,
         done(socket, "controllers.notifications.all_notifications_where_successfully_destroyed")}

      _ ->
        {:noreply, DawarichWeb.NotificationSession.Native.refuse(socket)}
    end
  end

  defp refresh(socket) do
    case Notifications.page(socket.assigns.current_scope, socket.assigns.page) do
      {:ok, page} ->
        assign(
          socket,
          Map.update!(
            page,
            :notifications,
            &Notifications.localize(
              &1,
              Dawarich.UserSettings.get(socket.assigns.current_user),
              socket.assigns.now
            )
          )
        )

      _ ->
        DawarichWeb.NotificationSession.Native.refuse(socket)
    end
  end

  defp done(socket, key) do
    case Notifications.unread(socket.assigns.current_scope) do
      {:ok, unread} ->
        socket
        |> assign(:navbar, Map.put(socket.assigns.navbar, :unread, unread))
        |> put_flash(:notice, t(socket.assigns.locale, key, %{}))
        |> push_patch(to: "/notifications")

      _ ->
        DawarichWeb.NotificationSession.Native.refuse(socket)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5 min-w-0" data-testid="native-notifications-root">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6 min-w-0">
        <h1 class="text-3xl font-bold">{t(@locale, "notifications.index.notifications", %{})}</h1>
        <div :if={@unread_on_page? or @notifications != []} class="flex flex-wrap gap-2 min-w-0">
          <button
            :if={@unread_on_page?}
            type="button"
            class="btn btn-sm btn-primary h-auto min-h-8 whitespace-normal"
            phx-click="mark_all_as_read"
          >{t(@locale, "notifications.index.mark_all_as_read", %{})}</button>
          <button
            :if={@notifications != []}
            type="button"
            class="btn btn-sm btn-warning h-auto min-h-8 whitespace-normal"
            phx-click={
              JS.push("choose_notifications_delete_all")
              |> JS.dispatch("dawarich:open-dialog", to: "#notifications-delete-dialog")
            }
          >{t(@locale, "notifications.index.delete_all", %{})}</button>
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
      <div id="notifications" class="w-full max-w-2xl mx-auto min-w-0">
        <.card
          :for={notification <- @notifications}
          notification={notification}
          locale={@locale}
          now={@now}
        />
      </div>
      <.dialog
        locale={@locale}
        target={@delete_target}
        id="notifications-delete-dialog"
        title_id="notifications-delete-title"
        title={
          t(@locale, "notifications.index.are_you_sure_you_want_to_delete_all_notifications", %{})
        }
        cancel="cancel_notifications_delete_all"
        confirm="confirm_notifications_delete_all"
      />
    </div>
    """
  end
end
