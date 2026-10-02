defmodule DawarichWeb.MapControls do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [map_path: 1, human_date: 2]

  alias DawarichWeb.{Icon, Params}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  attr :page, :map, required: true
  attr :params, :map, required: true
  attr :locale, :string, required: true

  def date_navigation(assigns) do
    w = assigns.page.window
    keep = %{"import_id" => assigns.params["import_id"], "panel" => assigns.params["panel"]}

    link = fn {first, last} ->
      map_path(Map.merge(keep, %{"start_at" => first, "end_at" => last}))
    end

    assigns =
      assign(assigns,
        w: w,
        action: map_path(%{"import_id" => assigns.params["import_id"]}),
        prev: link.(w.prev),
        next: link.(w.next),
        today: link.(w.today),
        week: link.({w.week_start, elem(w.today, 1)}),
        month: link.({w.month_start, elem(w.today, 1)}),
        share:
          "/share_links/hub?" <>
            Params.to_query(%{
              "end_date" => Date.to_iso8601(w.end_date),
              "start_date" => Date.to_iso8601(w.start_date)
            })
      )

    ~H"""
    <div
      class="w-full px-4 bg-base-100 border-b border-base-300"
      data-controller="map-controls"
      data-map-controls-locale-value={@locale}
      data-map-controls-timezone-value={@w.iana}
    >
      <div class="lg:hidden flex justify-center">
        <button type="button" data-action="click->map-controls#toggle" class="btn btn-primary w-96">
          <span data-map-controls-target="toggleIcon"><Icon.icon name="chevron-down" class="size-6" /></span>
          <span class="ml-2" data-map-controls-target="mobileLabel">{human_date(
            @locale,
            @w.start_date
          )}</span>
        </button>
      </div>
      <div
        data-map-controls-target="panel"
        class="hidden lg:!block bg-base-100 rounded-lg p-4 mt-2 lg:mt-0 container mx-auto"
      >
        <form action={@action} accept-charset="UTF-8" method="get">
          <input
            :if={is_binary(@params["panel"]) and Ruby.present?(@params["panel"])}
            value={@params["panel"]}
            type="hidden"
            name="panel"
            id="panel"
          />
          <div class="flex flex-col space-y-4 lg:flex-row lg:space-y-0 lg:space-x-4 lg:items-center">
            <div
              class="w-full lg:w-1/12 tooltip tooltip-bottom"
              data-tip={human_date(@locale, @w.prev_date)}
            >
              <a class="btn btn-sm border border-base-300 hover:btn-ghost w-full" href={@prev}><Icon.icon
                name="chevron-left"
                class="size-6"
              /></a>
            </div>
            <div
              class="w-full lg:w-2/12 tooltip tooltip-bottom"
              data-tip={s(@locale, "start_date_and_time")}
            >
              <input
                max="9999-12-31T23:59"
                class="input input-sm input-bordered hover:cursor-pointer hover:input-primary w-full"
                data-map-controls-target="start"
                type="datetime-local"
                value={@w.start_local}
                name="start_at"
                id="start_at"
              />
            </div>
            <div
              class="w-full lg:w-2/12 tooltip tooltip-bottom"
              data-tip={s(@locale, "end_date_and_time")}
            >
              <input
                max="9999-12-31T23:59"
                class="input input-sm input-bordered hover:cursor-pointer hover:input-primary w-full"
                data-map-controls-target="end"
                type="datetime-local"
                value={@w.end_local}
                name="end_at"
                id="end_at"
              />
            </div>
            <div
              class="w-full lg:w-1/12 tooltip tooltip-bottom"
              data-tip={human_date(@locale, @w.next_date)}
            >
              <a class="btn btn-sm border border-base-300 hover:btn-ghost w-full" href={@next}><Icon.icon
                name="chevron-right"
                class="size-6"
              /></a>
            </div>
            <div class="w-full lg:w-1/12">
              <div class="flex flex-col space-y-2">
                <input
                  type="submit"
                  name="commit"
                  value={s(@locale, "search")}
                  class="btn btn-sm btn-primary hover:btn-info w-full"
                  data-disable-with={s(@locale, "search")}
                />
              </div>
            </div>
            <div class="w-full lg:w-1/12">
              <div class="flex flex-col space-y-2 text-center">
                <a class="btn btn-sm border border-base-300 hover:btn-ghost w-full" href={@today}>{s(
                  @locale,
                  "today"
                )}</a>
              </div>
            </div>
            <div class="w-full lg:w-2/12">
              <div class="flex flex-col space-y-2 text-center">
                <a class="btn btn-sm border border-base-300 hover:btn-ghost w-full" href={@week}>{s(
                  @locale,
                  "last_7_days"
                )}</a>
              </div>
            </div>
            <div class="w-full lg:w-2/12">
              <div class="flex flex-col space-y-2 text-center">
                <a class="btn btn-sm border border-base-300 hover:btn-ghost w-full" href={@month}>{s(
                  @locale,
                  "last_month"
                )}</a>
              </div>
            </div>
            <div class="w-full lg:w-1/12 relative">
              <a
                class="btn btn-sm border border-base-300 hover:btn-ghost w-full flex-nowrap"
                data-turbo-frame="share-link-modal"
                data-testid="timeline-share-button"
                href={@share}
              >
                <Icon.icon name="share" class="w-4 h-4" />
                <span class="ml-1">{s(@locale, "share")}</span>
              </a>
              <turbo-frame id="live-share-indicator" class="contents">
                <span
                  :if={@page.live_share}
                  class="absolute -top-1 -right-1 w-2.5 h-2.5 bg-green-500 rounded-full animate-pulse ring-2 ring-base-100 pointer-events-none"
                  data-testid="live-share-dot"
                  title={t(@locale, "shared.map.share_indicator.live_location_is_being_shared", %{})}
                ></span>
              </turbo-frame>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "shared.map.date_navigation_v2." <> key, %{})

  attr :locale, :string, required: true

  def webgl_error(assigns) do
    ~H"""
    <div data-maps--maplibre-target="webglError" class="hidden">
      <div class="flex items-center justify-center h-full bg-base-200 text-center p-8">
        <div>
          <h3 class="text-lg font-bold mb-2">
            {t(@locale, "map.maplibre.webgl_error.webgl_is_not_available", %{})}
          </h3>
          <p class="text-sm text-base-content/70">
            {t(
              @locale,
              "map.maplibre.webgl_error.map_v2_requires_webgl_to_render_maps_please_enable_hardware",
              %{}
            )}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
