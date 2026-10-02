defmodule DawarichWeb.ImportsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]

  alias Dawarich.Imports.{Events, UiRecords}
  alias DawarichWeb.{ImportsActions, ImportsContext, ImportsPolling, NumberFormat}

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Events.subscribe(socket.assigns.current_user.id)
    {:ok, assign(socket, polling: false)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    case UiRecords.get(ImportsContext.repo(), socket.assigns.current_user.id, id) do
      {:ok, record} ->
        points =
          if socket.assigns[:record] == record,
            do: socket.assigns.points,
            else: count_points(record.id)

        {:noreply,
         socket
         |> assign(
           record: record,
           points: points,
           created:
             Dawarich.UserTimeZone.local(socket.assigns.current_user.settings, record.created_at),
           notice: Phoenix.Flash.get(socket.assigns.flash, "notice"),
           page_title: t(socket.assigns.locale, "imports.show.import", %{})
         )
         |> ImportsPolling.schedule([record])}

      _ ->
        {:noreply, redirect(socket, to: "/imports")}
    end
  end

  defp count_points(id) do
    [[points]] =
      ImportsContext.repo().query!(
        "SELECT count(*) FROM public.points WHERE import_id=$1",
        [id],
        log: false
      ).rows

    points
  end

  @impl true
  def handle_info(:imports_refresh, socket), do: refresh(assign(socket, polling: false))
  def handle_info(:imports_changed, socket), do: refresh(socket)

  defp refresh(socket) do
    handle_params(
      %{"id" => socket.assigns.record.id},
      "",
      assign(socket, :now, DateTime.utc_now())
    )
  end

  @impl true
  def handle_event("delete_import", _, socket) do
    case ImportsActions.delete(socket.assigns.current_user, socket.assigns.record.id) do
      {:ok, _} ->
        refresh(socket)

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           t(socket.assigns.locale, "imports.table_row.deletion_stalled", %{})
         )}
    end
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
        />
        <a
          class="mt-2 rounded-lg py-3 px-5 bg-secondary-content inline-block font-medium"
          href={"/imports/#{@record.id}/edit"}
        >{t(@locale, "imports.show.edit_this_import", %{})}</a>
        <div class="inline-block ml-2">
          <form
            action={"/imports/#{@record.id}"}
            method="post"
            data-turbo="false"
            phx-submit="delete_import"
          >
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="import_id" value={@record.id} />
            <button
              type="submit"
              data-testid="import-delete"
              class="mt-2 rounded-lg py-3 px-5 bg-secondary-content font-medium"
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
          class="ml-2 rounded-lg py-3 px-5 bg-secondary-content inline-block font-medium"
          href="/imports"
        >{t(@locale, "imports.show.back_to_imports", %{})}</a>
      </div>
    </div>
    """
  end

  defp source(nil), do: ""
  defp source(index), do: Enum.at(UiRecords.sources(), index, "")
end
