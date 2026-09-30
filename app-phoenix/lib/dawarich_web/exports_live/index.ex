defmodule DawarichWeb.ExportsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.ExportRow, only: [row: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1, sort_link: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]

  @sortable ~w(name status created_at byte_size)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
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
     |> assign(Dawarich.ImportExportIndex.exports(socket.assigns.current_user, list))}
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
    <div class="w-full my-5">
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
            <table class="table w-full">
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
    </div>
    """
  end
end
