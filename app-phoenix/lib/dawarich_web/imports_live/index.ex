defmodule DawarichWeb.ImportsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ImportRow, only: [row: 1]
  import DawarichWeb.ListParts, only: [page_header: 1, sort_link: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @sortable ~w(name status created_at processed byte_size)
  @integrations [
    {"immich", "start_immich_import", "imports.index.import_from_immich"},
    {"photoprism", "start_photoprism_import", "imports.index.import_from_photoprism"}
  ]
  @columns [
    {"name", "imports.index.name", "w-auto"},
    {"byte_size", "imports.index.file_size", "w-[10%]"},
    {"processed", "imports.index.points", "text-right w-[10%]"},
    {"status", "imports.index.status", "w-[12%]"},
    {"created_at", "imports.index.created", "w-[18%]"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Dawarich.Imports.Events.subscribe(socket.assigns.current_user.id)
      Process.send_after(self(), :imports_refresh, 1000)
    end

    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "imports.index.imports", %{}),
       morph_page_refreshes: true
     )}
  end

  @impl true
  def handle_info(:imports_refresh, socket) do
    Process.send_after(self(), :imports_refresh, 1000)
    refresh(socket)
  end

  def handle_info(:imports_changed, socket), do: refresh(socket)

  defp refresh(socket) do
    if Dawarich.Accounts.get(socket.assigns.current_user.id) do
      {:noreply,
       socket
       |> assign(:now, DateTime.utc_now())
       |> assign(
         Dawarich.ImportExportIndex.imports(socket.assigns.current_user, socket.assigns.list)
       )}
    else
      {:noreply, redirect(socket, to: "/users/sign_in")}
    end
  end

  @impl true
  def handle_event("delete_import", %{"import_id" => id}, socket) do
    user = socket.assigns.current_user

    case DawarichWeb.ImportsActions.delete(user, id) do
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
  def handle_params(params, uri, socket) do
    query = URI.parse(uri).query || ""
    list = DawarichWeb.ListParams.parse(params, query, @sortable)
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(
       list: list,
       query: URI.decode_query(query),
       columns: @columns,
       integrations: integrations(user.settings)
     )
     |> assign(Dawarich.ImportExportIndex.imports(user, list))}
  end

  defp integrations(settings) do
    settings = if is_map(settings), do: settings, else: %{}

    for {name, job, key} <- @integrations,
        Ruby.present?(settings[name <> "_url"]) and Ruby.present?(settings[name <> "_api_key"]),
        do: {job, key}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="native-imports-root" class="w-full my-5">
      <.page_header title={t(@locale, "imports.index.imports", %{})}>
        <div :if={@integrations != []} class="join">
          <a href="/imports/new" class="btn btn-primary btn-sm join-item"><.icon
            name="circle-plus"
            class="w-4 h-4"
          /> {t(@locale, "imports.index.new_import", %{})}</a>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-primary btn-sm join-item"><.icon
              name="chevron-down"
              class="w-4 h-4"
            /></label>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-lg w-52 mt-1 border border-base-300"
            >
              <li :for={{job, key} <- @integrations}>
                <a
                  href={"/settings/background_jobs?job_name=" <> job}
                  data-turbo-confirm={t(@locale, "imports.index.are_you_sure", %{})}
                  data-turbo-method="post"
                ><.icon name="camera" class="w-4 h-4" /> {t(@locale, key, %{})}</a>
              </li>
            </ul>
          </div>
        </div>
        <a :if={@integrations == []} href="/imports/new" class="btn btn-primary btn-sm"><.icon
          name="circle-plus"
          class="w-4 h-4"
        /> {t(@locale, "imports.index.new_import", %{})}</a>
      </.page_header>
      <div id="imports" class="min-w-full">
        <div
          :if={@entries == []}
          class="text-center py-16 px-8 bg-base-200 rounded-xl border-2 border-dashed border-base-300"
        >
          <h3 class="text-xl font-bold mb-3">{t(@locale, "imports.index.no_imports_yet", %{})}</h3>
          <p class="text-base-content/50 mb-6 max-w-sm mx-auto">
            {t(
              @locale,
              "imports.index.import_your_location_data_from_google_maps_timeline_gpx_files",
              %{}
            )}
          </p>
          <a href="/imports/new" class="btn btn-primary"><.icon name="circle-plus" class="w-4 h-4" /> {t(
            @locale,
            "imports.index.create_your_first_import",
            %{}
          )}</a>
        </div>
        <%= if @entries != [] do %>
          <div class="flex justify-center mb-4">
            <.paginator
              locale={@locale}
              path="/imports"
              query={@query}
              page={@list.page}
              total_pages={@total_pages}
            />
          </div>
          <div class="border border-base-300 rounded-xl overflow-x-auto">
            <table class="table w-full">
              <thead class="bg-base-200">
                <tr>
                  <th
                    :for={{column, key, width} <- @columns}
                    class={"px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 " <> width}
                  >
                    <.sort_link
                      title={t(@locale, key, %{})}
                      column={column}
                      path="/imports"
                      list={@list}
                    />
                  </th>
                  <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 text-right w-[15%]">
                    {t(
                      @locale,
                      "imports.index.actions",
                      %{}
                    )}
                  </th>
                </tr>
              </thead>
              <tbody
                data-controller="imports"
                data-imports-target="index"
                data-user-id={@current_user.id}
              >
                <.row
                  :for={import <- @entries}
                  import={import}
                  locale={@locale}
                  now={@now}
                  rails_csrf_token={@rails_csrf_token}
                />
              </tbody>
            </table>
          </div>
          <div class="flex justify-center mt-4">
            <.paginator
              locale={@locale}
              path="/imports"
              query={@query}
              page={@list.page}
              total_pages={@total_pages}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
