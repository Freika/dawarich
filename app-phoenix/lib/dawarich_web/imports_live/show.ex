defmodule DawarichWeb.ImportsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Imports.{UiRecords, Events}
  @statuses ~w(created processing completed failed deleting)
  @impl true
  def mount(_, _, socket) do
    if connected?(socket),
      do:
        (
          Events.subscribe(socket.assigns.current_user.id)
          Process.send_after(self(), :imports_refresh, 1000)
        )

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    case UiRecords.get(DawarichWeb.ImportsContext.repo(), socket.assigns.current_user.id, id) do
      {:ok, record} ->
        {:noreply,
         assign(socket,
           record: record,
           sources: UiRecords.sources(),
           status: Enum.at(@statuses, record.status),
           extraction_available:
             Dawarich.Imports.Postprocessing.Policy.extracts?(%{
               record
               | additional_data_extraction_status: 0
             }),
           page_title: record.name
         )}

      _ ->
        {:noreply, redirect(socket, to: "/imports")}
    end
  end

  @impl true
  def handle_info(:imports_refresh, socket) do
    Process.send_after(self(), :imports_refresh, 1000)
    refresh(socket)
  end

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
    user = socket.assigns.current_user

    case Dawarich.Imports.Destroy.enqueue(
           DawarichWeb.ImportsContext.repo(),
           user.id,
           socket.assigns.record.id,
           DawarichWeb.ImportsContext.for_user(user)
         ) do
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
      data-testid="native-imports-root"
      data-import-id={@record.id}
      class="mx-auto md:w-2/3 w-full my-5"
    >
      <%= if @live_action==:edit do %>
        <h1 class="font-bold text-3xl">{t(@locale, "imports.edit.editing_import", %{})}</h1>
        <form
          action={"/imports/#{@record.id}"}
          method="post"
          data-turbo="false"
          class="form-body mt-4"
        >
          <input type="hidden" name="authenticity_token" value={@rails_csrf_token} /><input
            type="hidden"
            name="_method"
            value="patch"
          />
          <label class="form-control"><span class="label-text">{t(@locale, "imports.import.name", %{})}</span><input
            name="import[name]"
            value={@record.name}
            class="input input-bordered"
          /></label>
          <label class="form-control"><span class="label-text">{t(
            @locale,
            "javascript.map_info.source",
            %{}
          )}</span><select
            name="import[source]"
            class="select select-bordered"
          >
            <option value="" selected={is_nil(@record.source)}></option><option
              :for={{source, index} <- Enum.with_index(@sources)}
              value={source}
              selected={@record.source == index}
            >
              {t(@locale, "enums.import.source." <> source, %{})}
            </option>
          </select></label>
          <button class="btn btn-primary my-4">{t(@locale, "imports.edit.editing_import", %{})}</button>
        </form>
      <% else %>
        <h1 class="font-bold text-3xl">{@record.name}</h1>
        <span data-status-display class="badge my-4">{t(
          @locale,
          "enums.import.status." <> @status,
          %{}
        )}</span>
        <table class="table">
          <tbody>
            <tr>
              <th>{t(@locale, "imports.import.imported_points", %{})}</th><td data-points-count>
                {@record.processed || 0}
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@record.error_message} class="text-error">{@record.error_message}</p>
        <a href={"/imports/#{@record.id}/edit"} class="btn my-4">{t(
          @locale,
          "imports.show.edit_this_import",
          %{}
        )}</a>
        <a
          :if={@record.source_blob_id}
          href={"/imports/#{@record.id}/download"}
          data-turbo="false"
          class="btn my-4"
        >{t(@locale, "imports.table_row.download_file", %{})}</a>
        <form
          :if={@record.status != 4}
          action={"/imports/#{@record.id}"}
          method="post"
          data-turbo="false"
          phx-submit="delete_import"
          class="inline"
        >
          <input type="hidden" name="authenticity_token" value={@rails_csrf_token} /><input
            type="hidden"
            name="_method"
            value="delete"
          /><button data-testid="import-delete" class="btn btn-error">{t(
            @locale,
            "imports.show.destroy_this_import",
            %{}
          )}</button>
        </form>
        <DawarichWeb.ImportsExtractionCard.card
          record={@record}
          locale={@locale}
          csrf={@rails_csrf_token}
          context={
            %{zone: Dawarich.UserTimeZone.name(@current_user.settings), now: DateTime.utc_now()}
          }
        />
      <% end %>
      <a href="/imports" class="btn my-4">{t(@locale, "imports.show.back_to_imports", %{})}</a>
    </div>
    """
  end
end
