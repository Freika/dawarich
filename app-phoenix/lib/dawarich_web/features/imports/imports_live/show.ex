defmodule DawarichWeb.ImportsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]

  alias Dawarich.Imports.UiRecords
  alias DawarichWeb.{NumberFormat, ImportsStallTimer}

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Dawarich.Imports.subscribe(socket.assigns.current_scope)
    {:ok, assign(socket, polling: false)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    previous = socket.assigns[:record]

    case Dawarich.Imports.get(socket.assigns.current_scope, id, details: true, previous: previous) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(
           now: ImportsStallTimer.now(socket),
           record: record,
           points: record.points,
           created: record.created,
           notice: Phoenix.Flash.get(socket.assigns.flash, "notice"),
           page_title: t(socket.assigns.locale, "imports.show.import", %{})
         )
         |> ImportsStallTimer.schedule([record])}

      {:error, reason} ->
        to = if reason == :stale_session, do: "/users/sign_in", else: "/imports"

        {:noreply,
         socket
         |> ImportsStallTimer.cancel()
         |> assign(record: nil, points: nil)
         |> redirect(to: to)}
    end
  end

  @impl true
  def handle_info(:imports_refresh, socket), do: {:noreply, socket}

  def handle_info({:import_stall_deadline, token}, socket) do
    if ImportsStallTimer.current?(socket, token), do: refresh(socket), else: {:noreply, socket}
  end

  def handle_info({:domain_changed, owner, :imports}, socket)
      when owner == socket.assigns.current_user.id do
    DawarichWeb.ImportsInvalidations.coalesce(owner)
    refresh(socket)
  end

  def handle_info(:imports_changed, socket), do: refresh(socket)

  defp refresh(socket) do
    handle_params(
      %{"id" => socket.assigns.record.id},
      "",
      assign(socket, :now, ImportsStallTimer.now(socket))
    )
  end

  @impl true
  def handle_event("delete_import", _, socket) do
    case Dawarich.Imports.delete(socket.assigns.current_scope, socket.assigns.record.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> ImportsStallTimer.cancel()
         |> put_flash(
           :notice,
           t(socket.assigns.locale, "controllers.imports.import_is_being_deleted", %{})
         )
         |> redirect(to: "/imports")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           t(socket.assigns.locale, "imports.table_row.deletion_stalled", %{})
         )}
    end
  end

  def handle_event("extract_import", params, socket), do: extraction(socket, :extract, params)
  def handle_event("remove_extraction", _, socket), do: extraction(socket, :remove, %{})

  defp extraction(socket, action, params) do
    scope = socket.assigns.current_scope
    id = socket.assigns.record.id

    result =
      if action == :extract,
        do: Dawarich.Imports.extract(scope, id, params),
        else: Dawarich.Imports.remove_extraction(scope, id)

    case result do
      {:ok, _} ->
        refresh(push_event(socket, "close-dialog", %{id: "extraction-dialog-#{id}"}))

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, t(socket.assigns.locale, "imports.table_row.deletion_stalled", %{}))}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    ImportsStallTimer.cancel(socket)
    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="mx-auto md:w-2/3 w-full flex"
      data-testid="native-imports-root"
    >
      <div class="mx-auto">
        <p
          :if={@notice}
          class="py-2 px-3 bg-green-50 mb-5 text-green-500 font-medium rounded-lg inline-block"
          id="notice"
        >
          {@notice}
        </p>
        <div id={"import_#{@record.id}"}>
          <table class="table">
            <thead>
              <tr>
                <th>{t(@locale, "imports.import.name", %{})}</th>
                <th>{t(@locale, "imports.import.imported_points", %{})}</th>
                <th>{t(@locale, "imports.import.created_at", %{})}</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>
                  <a class="underline hover:no-underline" href={"/imports/#{@record.id}"}>{@record.name}</a>
                  ({source(@record.source)})
                </td>
                <td data-points-count>{NumberFormat.delimited(@locale, @points)}</td>
                <td><.human_datetime locale={@locale} at={@created} /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <DawarichWeb.ImportsExtractionCard.card
          record={@record}
          locale={@locale}
          csrf={@rails_csrf_token}
          now={@now}
          native={true}
        />
        <a
          class="btn mt-2"
          href={"/imports/#{@record.id}/edit"}
        >{t(@locale, "imports.show.edit_this_import", %{})}</a>
        <div class="inline-block ml-2">
          <form phx-submit="delete_import" action={"/imports/#{@record.id}"} method="post">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            <input type="hidden" name="import_id" value={@record.id} />
            <button
              type="submit"
              data-testid="import-delete"
              class="btn btn-outline btn-error mt-2"
              data-confirm={
                t(
                  @locale,
                  "imports.show.are_you_sure_this_action_will_delete_all_points_imported",
                  %{}
                )
              }
            >{t(@locale, "imports.show.destroy_this_import", %{})}</button>
          </form>
        </div>
        <a
          class="btn mt-2 ml-2"
          href="/imports"
        >{t(@locale, "imports.show.back_to_imports", %{})}</a>
      </div>
    </div>
    """
  end

  defp source(nil), do: ""
  defp source(index), do: Enum.at(UiRecords.sources(), index, "")
end
