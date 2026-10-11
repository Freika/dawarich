defmodule DawarichWeb.ExportsLive.Index do
  @moduledoc false
  alias Phoenix.LiveView.JS
  use DawarichWeb, :live_view

  import DawarichWeb.ExportRow, only: [row: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1, sort_link: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]

  @sortable ~w(name status created_at byte_size)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Dawarich.Exports.subscribe(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       delete_target: nil,
       page_title: t(socket.assigns.locale, "exports.index.exports", %{}),
       points_url: (socket.assigns[:base_url] || "") <> "/points",
       columns: columns(socket.assigns.locale)
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    query = URI.parse(uri).query || ""
    list = DawarichWeb.ListParams.parse(params, query, @sortable)

    {:noreply,
     socket
     |> assign(list: list, query: URI.decode_query(query))
     |> refresh()}
  end

  @impl true
  def handle_info({:domain_changed, owner, :exports}, socket)
      when owner == socket.assigns.current_user.id do
    coalesce(owner, 100)
    {:noreply, refresh(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("choose_export_delete", %{"id" => id}, socket) do
    socket = refresh(socket)
    target = Enum.find(socket.assigns.entries, &(to_string(&1.id) == id))
    {:noreply, assign(socket, :delete_target, target && Map.take(target, [:id, :name]))}
  end

  def handle_event("cancel_export_delete", _, socket),
    do: {:noreply, assign(socket, :delete_target, nil)}

  def handle_event("confirm_export_delete", _, %{assigns: %{delete_target: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm_export_delete", _, socket) do
    result =
      Dawarich.Exports.delete(socket.assigns.current_scope, socket.assigns.delete_target.id)

    socket = assign(socket, :delete_target, nil)

    case result do
      {:ok, :deleted} ->
        {:noreply,
         socket
         |> put_flash(
           :notice,
           t(socket.assigns.locale, "controllers.exports.export_was_successfully_destroyed", %{})
         )
         |> refresh()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(
           :alert,
           t(socket.assigns.locale, "controllers.application.admin_action_failed", %{})
         )
         |> refresh()}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp refresh(socket) do
    case Dawarich.Exports.page(socket.assigns.current_scope, socket.assigns.list) do
      {:ok, page} ->
        target = socket.assigns.delete_target
        target = if target && Enum.any?(page.entries, &(&1.id == target.id)), do: target
        socket |> assign(page) |> assign(delete_target: target, now: DateTime.utc_now())

      {:error, _} ->
        socket |> assign(entries: [], delete_target: nil) |> redirect(to: "/users/sign_in")
    end
  end

  defp coalesce(_, 0), do: :ok

  defp coalesce(owner, left) do
    receive do
      {:domain_changed, ^owner, :exports} -> coalesce(owner, left - 1)
    after
      0 -> :ok
    end
  end

  defp columns(locale) do
    [
      {"name", t(locale, "exports.index.name", %{}), "w-[40%]"},
      {"byte_size", "File size", "w-[12%]"},
      {"status", t(locale, "exports.index.status", %{}), "w-[15%]"},
      {"created_at", t(locale, "exports.index.created", %{}), "w-[20%]"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5 min-w-0" data-testid="native-exports-root">
      <.page_header title={t(@locale, "exports.index.exports", %{})} />
      <div id="exports" class="min-w-full">
        <div
          :if={@entries == []}
          class="text-center py-16 px-8 bg-base-200 rounded-xl border-2 border-dashed border-base-300"
        >
          <h3 class="text-xl font-bold mb-3">{t(@locale, "exports.index.no_exports_yet", %{})}</h3>
          <p class="text-base-content/50 mb-6 max-w-sm mx-auto">
            {t(@locale, "exports.index.exports_are_created_from_the", %{})}
            <a href={@points_url} class="link link-primary">{t(@locale, "exports.index.points", %{})}</a> {t(
              @locale,
              "exports.index.page_select_a_date_range_and_export_to_geojson_or",
              %{}
            )}
          </p>
          <a href={@points_url} class="btn btn-primary"><.icon name="map-pin" class="w-4 h-4" /> {t(
            @locale,
            "exports.index.go_to_points",
            %{}
          )}</a>
        </div>
        <%= if @entries != [] do %>
          <div class="flex justify-center mb-4">
            <.paginator
              locale={@locale}
              path="/exports"
              query={@query}
              page={@list.page}
              total_pages={@total_pages}
            />
          </div>
          <div class="border border-base-300 rounded-xl overflow-x-auto">
            <table class="table w-full table-fixed max-sm:[&_th]:p-1 max-sm:[&_td]:p-1 max-sm:text-xs max-sm:[&_.whitespace-nowrap]:whitespace-normal [overflow-wrap:anywhere]">
              <thead class="bg-base-200">
                <tr>
                  <th
                    :for={{column, title, width} <- @columns}
                    class={"px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 " <> width}
                  >
                    <.sort_link title={title} column={column} path="/exports" list={@list} />
                  </th>
                  <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 text-right w-[13%]">
                    {t(
                      @locale,
                      "exports.index.actions",
                      %{}
                    )}
                  </th>
                </tr>
              </thead>
              <tbody>
                <.row :for={export <- @entries} export={export} locale={@locale} />
              </tbody>
            </table>
          </div>
          <div class="flex justify-center mt-4">
            <.paginator
              locale={@locale}
              path="/exports"
              query={@query}
              page={@list.page}
              total_pages={@total_pages}
            />
          </div>
        <% end %>
      </div>
      <dialog
        id="export-delete-dialog"
        class="modal"
        open={@delete_target != nil}
        phx-mounted={JS.ignore_attributes("open")}
        phx-window-keydown="cancel_export_delete"
        phx-key="Escape"
        aria-labelledby="export-delete-title"
      >
        <div class="modal-box min-w-0 [overflow-wrap:anywhere]">
          <h2 id="export-delete-title" class="text-lg font-bold">
            {t(@locale, "exports.table_row.are_you_sure", %{})}
          </h2>
          <p :if={@delete_target} class="py-4">{@delete_target.name}</p>
          <div class="modal-action flex-wrap">
            <button
              type="button"
              class="btn"
              phx-click={
                JS.push("cancel_export_delete")
                |> JS.dispatch("dawarich:close-dialog", to: "#export-delete-dialog")
              }
            >{t(@locale, "javascript.common.cancel", %{})}</button>
            <button
              type="button"
              class="btn btn-error"
              disabled={is_nil(@delete_target)}
              phx-click={
                JS.push("confirm_export_delete")
                |> JS.dispatch("dawarich:close-dialog", to: "#export-delete-dialog")
              }
              phx-disable-with={t(@locale, "javascript.common.delete", %{})}
            >{t(@locale, "javascript.common.delete", %{})}</button>
          </div>
        </div>
        <button
          type="button"
          class="modal-backdrop"
          aria-label={t(@locale, "javascript.common.close", %{})}
          phx-click={
            JS.push("cancel_export_delete")
            |> JS.dispatch("dawarich:close-dialog", to: "#export-delete-dialog")
          }
        ></button>
      </dialog>
    </div>
    """
  end
end
