defmodule DawarichWeb.PointListControls do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  alias DawarichWeb.PointListFormat, as: F

  attr :locale, :string, required: true
  attr :window, :map, required: true
  attr :imports, :list, required: true
  attr :query, :map, required: true
  attr :summary, :any, required: true
  attr :form, :any, required: true

  def controls(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl bg-base-200/50 p-4 mb-5 min-w-0">
      <.form for={@form} id="point_filters" phx-submit="filter">
        <input type="hidden" name="order_by" value={@query["order_by"]} />
        <div class="flex flex-col flex-wrap gap-3 md:flex-row md:items-end">
          <div class="flex-1 min-w-0">
            <label for="start_at" class="block text-sm">Start at</label>
            <input
              type="datetime-local"
              name="start_at"
              id="start_at"
              max="9999-12-31T23:59"
              class="input input-bordered input-sm w-full min-w-0"
              value={@window.start_local}
            />
          </div>
          <div class="flex-1 min-w-0">
            <label for="end_at" class="block text-sm">End at</label>
            <input
              type="datetime-local"
              name="end_at"
              id="end_at"
              max="9999-12-31T23:59"
              class="input input-bordered input-sm w-full min-w-0"
              value={@window.end_local}
            />
          </div>
          <div class="flex-1 min-w-0">
            <label for="import_id" class="block text-sm">Import</label>
            <select
              name="import_id"
              id="import_id"
              class="select select-bordered select-sm w-full min-w-0"
            >
              <option value="">{t(@locale, "points.index.all_imports", %{})}</option>
              <option
                :for={entry <- @imports}
                value={entry.id}
                selected={@query["import_id"] == to_string(entry.id)}
              >
                {entry.name}
              </option>
            </select>
          </div>
          <div class="flex-1 min-w-0">
            <label for="import_search" class="block text-sm">{t(@locale, "points.index.search", %{})}: Import</label>
            <input
              type="search"
              name="import_search"
              id="import_search"
              value={@query["import_search"]}
              class="input input-bordered input-sm w-full min-w-0"
            />
          </div>
          <button
            type="submit"
            class="btn btn-primary btn-sm h-auto min-h-8 whitespace-normal"
            phx-disable-with={t(@locale, "points.index.search", %{})}
          >{t(@locale, "points.index.search", %{})}</button>
        </div>
      </.form>
    </div>
    <div class="flex flex-wrap min-w-0 items-center justify-between gap-3 mb-4">
      <div class="text-sm break-words">{@summary}</div>
      <div class="flex flex-wrap gap-2">
        <button
          :for={{format, label} <- [{"json", "geojson"}, {"gpx", "gpx"}]}
          type="button"
          class="btn btn-outline btn-xs h-auto whitespace-normal"
          phx-click="export"
          phx-value-format={format}
        >
          <.icon name="arrow-big-down" class="w-3.5 h-3.5" /> {t(@locale, "points.index.export", %{})}: {t(
            @locale,
            "points.index." <> label,
            %{}
          )}
        </button>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :query, :map, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :class, :string, required: true

  def pagination(assigns) do
    ~H"""
    <div class={@class}>
      <.paginator
        :if={@total_pages > 1}
        locale={@locale}
        path="/points"
        query={@query}
        page={@page}
        total_pages={@total_pages}
      />
    </div>
    """
  end

  def bulk_action(query),
    do:
      F.url(
        "/points/bulk_destroy",
        Map.merge(%{"action" => "index", "controller" => "points"}, query)
      )

  def order_url(query) do
    next = if query["order_by"] == "asc", do: "desc", else: "asc"
    F.url("/points", query |> Map.drop(["page"]) |> Map.put("order_by", next))
  end
end
