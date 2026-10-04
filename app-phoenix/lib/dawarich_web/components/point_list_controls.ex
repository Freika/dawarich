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

  def controls(assigns) do
    assigns =
      assign(
        assigns,
        :filter_action,
        F.url("/points", %{"import_id" => assigns.query["import_id"]})
      )

    ~H"""
    <div class="border border-base-300 rounded-xl bg-base-200/50 p-4 mb-5">
      <form action={@filter_action} accept-charset="UTF-8" method="get" data-turbo-method="get">
        <div class="flex flex-col gap-3 md:flex-row md:items-end">
          <div class="flex-1">
            <label
              for="start_at"
              class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-1 block"
            >Start at</label>
            <input
              type="datetime-local"
              name="start_at"
              id="start_at"
              max="9999-12-31T23:59"
              class="input input-bordered input-sm w-full"
              value={@window.start_local}
            />
          </div>
          <div class="flex-1">
            <label
              for="end_at"
              class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-1 block"
            >End at</label>
            <input
              type="datetime-local"
              name="end_at"
              id="end_at"
              max="9999-12-31T23:59"
              class="input input-bordered input-sm w-full"
              value={@window.end_local}
            />
          </div>
          <div class="flex-1">
            <label
              for="import"
              class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-1 block"
            >Import</label>
            <select
              name="import_id"
              id="import_id"
              class="select select-bordered select-sm text-sm w-full"
            >
              <option value="">{t(@locale, "points.index.all_imports", %{})}</option>
              <option
                :for={entry <- @imports}
                value={entry.id}
                selected={if @query["import_id"] == to_string(entry.id), do: "selected"}
              >
                {entry.name}
              </option>
            </select>
          </div>
          <input
            type="submit"
            name="commit"
            value={t(@locale, "points.index.search", %{})}
            class="btn btn-primary btn-sm"
            data-disable-with={t(@locale, "points.index.search", %{})}
          />
        </div>
      </form>
    </div>
    <div class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between mb-4">
      <div class="text-sm text-base-content/50">{@summary}</div>
      <div class="flex flex-wrap items-center gap-2">
        <div class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-outline btn-xs gap-1">
            <.icon name="arrow-big-down" class="w-3.5 h-3.5" /> {t(
              @locale,
              "points.index.export",
              %{}
            )}
            <.icon name="chevron-down" class="w-3 h-3" />
          </label>
          <ul
            tabindex="0"
            class="dropdown-content z-[50] menu p-2 shadow-lg bg-base-100 rounded-lg w-48 mt-1 border border-base-300"
          >
            <li :for={
              {format, icon, label} <- [{"json", "earth", "geojson"}, {"gpx", "route", "gpx"}]
            }>
              <a
                href={export_url(@window, format)}
                data-turbo-confirm={t(@locale, "points.index.export_as_" <> label, %{})}
                data-turbo-method="post"
              >
                <.icon name={icon} class="w-4 h-4" /> {t(@locale, "points.index." <> label, %{})}
              </a>
            </li>
          </ul>
        </div>
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

    F.url(
      "/points",
      query |> Map.take(~w(import_id start_at end_at)) |> Map.put("order_by", next)
    )
  end

  defp export_url(window, format),
    do:
      F.url("/exports", %{
        "file_format" => format,
        "start_at" => F.datetime_param(window.start, window.zone),
        "end_at" => F.datetime_param(window.end, window.zone)
      })
end
