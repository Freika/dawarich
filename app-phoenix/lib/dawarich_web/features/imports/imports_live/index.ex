defmodule DawarichWeb.ImportsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ImportRow, only: [row: 1]
  import DawarichWeb.ListParts, only: [page_header: 1, sort_link: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]

  alias DawarichWeb.ImportsStallTimer

  @sortable ~w(name status created_at processed byte_size)
  @columns [
    {"name", "imports.index.name", "w-auto"},
    {"byte_size", "imports.index.file_size", "w-[10%]"},
    {"processed", "imports.index.points", "text-right w-[10%]"},
    {"status", "imports.index.status", "w-[12%]"},
    {"created_at", "imports.index.created", "w-[18%]"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Dawarich.Imports.subscribe(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "imports.index.imports", %{}),
       morph_page_refreshes: true,
       polling: false,
       provider_requests: MapSet.new()
     )}
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
    case Dawarich.Imports.page(socket.assigns.current_scope, socket.assigns.list) do
      {:ok, page} ->
        integrations =
          for name <- page.providers,
              do: {"start_#{name}_import", "imports.index.import_from_#{name}"}

        {:noreply,
         socket
         |> assign(:now, ImportsStallTimer.now(socket))
         |> assign(page)
         |> assign(:integrations, integrations)
         |> ImportsStallTimer.schedule(page.entries)}

      {:error, _} ->
        {:noreply,
         socket
         |> ImportsStallTimer.cancel()
         |> assign(entries: [])
         |> redirect(to: "/users/sign_in")}
    end
  end

  @impl true
  def handle_event("delete_import", %{"import_id" => id}, socket) do
    case Dawarich.Imports.delete(socket.assigns.current_scope, id) do
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

  def handle_event("request_provider", %{"job" => job}, socket) do
    if MapSet.member?(socket.assigns.provider_requests, job) do
      {:noreply, socket}
    else
      case Dawarich.Imports.request_provider(socket.assigns.current_scope, job) do
        {:ok, :queued} ->
          {:noreply,
           socket
           |> update(:provider_requests, &MapSet.put(&1, job))
           |> put_flash(
             :notice,
             t(
               socket.assigns.locale,
               "controllers.settings.background_jobs.job_was_successfully_created",
               %{}
             )
           )}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :alert,
             t(socket.assigns.locale, "controllers.application.admin_action_failed", %{})
           )}
      end
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    query = URI.parse(uri).query || ""
    list = DawarichWeb.ListParams.parse(params, query, @sortable)

    socket =
      assign(socket,
        list: list,
        query: URI.decode_query(query),
        columns: @columns,
        integrations: []
      )

    refresh(socket)
  end

  @impl true
  def terminate(_reason, socket) do
    ImportsStallTimer.cancel(socket)
    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="native-imports-root" class="w-full min-w-0 my-5">
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
                  href="#"
                  data-native-href={"/settings/background_jobs?job_name=#{job}"}
                  phx-click="request_provider"
                  phx-value-job={job}
                  aria-disabled={if(MapSet.member?(@provider_requests, job), do: "true")}
                  data-confirm={t(@locale, "imports.index.are_you_sure", %{})}
                >
                  <.icon name="camera" class="w-4 h-4" /> {t(@locale, key, %{})}
                </a>
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
          <a href="/imports/new" class="btn btn-primary h-auto min-h-12 whitespace-normal"><.icon
            name="circle-plus"
            class="w-4 h-4"
          /> {t(
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
              <tbody>
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
