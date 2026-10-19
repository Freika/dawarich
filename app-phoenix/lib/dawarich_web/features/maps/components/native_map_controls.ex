defmodule DawarichWeb.NativeMapControls do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [human_date: 2]

  alias DawarichWeb.Icon
  alias DawarichWeb.MapLive.Commands
  alias Phoenix.LiveView.JS

  attr :url, :map, required: true
  attr :window, :map, required: true
  attr :locale, :string, required: true
  attr :live_share, :boolean, default: false

  def date_navigation(assigns) do
    w = assigns.window

    range = fn {first, last} ->
      Commands.path(assigns.url, %{"start_at" => first, "end_at" => last})
    end

    assigns =
      assign(assigns,
        prev: range.(w.prev),
        next: range.(w.next),
        today: range.(w.today),
        week: range.({w.week_start, elem(w.today, 1)}),
        month: range.({w.month_start, elem(w.today, 1)})
      )

    ~H"""
    <div class="w-full px-4 bg-base-100 border-b border-base-300">
      <div class="lg:hidden flex justify-center">
        <button
          type="button"
          class="btn btn-primary w-96"
          phx-click={JS.toggle_class("hidden", to: "#native-map-date-panel")}
        >
          <span><Icon.icon name="chevron-down" class="size-6" /></span>
          <span class="ml-2">{human_date(@locale, @window.start_date)}</span>
        </button>
      </div>
      <div
        id="native-map-date-panel"
        class="hidden lg:!block bg-base-100 rounded-lg p-4 mt-2 lg:mt-0 container mx-auto"
      >
        <form
          id="native-map-dates"
          action="/map/v2"
          accept-charset="UTF-8"
          method="get"
          phx-submit="map:dates"
        >
          <input
            :if={@url["panel"] not in [nil, ""]}
            type="hidden"
            name="panel"
            value={@url["panel"]}
          />
          <div class="flex flex-col space-y-4 lg:flex-row lg:space-y-0 lg:space-x-4 lg:items-center">
            <div
              class="w-full lg:w-1/12 tooltip tooltip-bottom"
              data-tip={human_date(@locale, @window.prev_date)}
            >
              <.link
                id="native-map-prev-day"
                patch={@prev}
                class="btn btn-sm border border-base-300 hover:btn-ghost w-full"
              >
                <Icon.icon name="chevron-left" class="w-4 h-4" />
              </.link>
            </div>
            <div
              class="w-full lg:w-2/12 tooltip tooltip-bottom"
              data-tip={s(@locale, "start_date_and_time")}
            >
              <input
                max="9999-12-31T23:59"
                class="input input-sm input-bordered hover:cursor-pointer hover:input-primary w-full"
                type="datetime-local"
                value={@window.start_local}
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
                type="datetime-local"
                value={@window.end_local}
                name="end_at"
                id="end_at"
              />
            </div>
            <div
              class="w-full lg:w-1/12 tooltip tooltip-bottom"
              data-tip={human_date(@locale, @window.next_date)}
            >
              <.link
                id="native-map-next-day"
                patch={@next}
                class="btn btn-sm border border-base-300 hover:btn-ghost w-full"
              >
                <Icon.icon name="chevron-right" class="w-4 h-4" />
              </.link>
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
                <.link
                  id="native-map-today"
                  patch={@today}
                  class="btn btn-sm border border-base-300 hover:btn-ghost w-full"
                >{s(@locale, "today")}</.link>
              </div>
            </div>
            <div class="w-full lg:w-2/12">
              <div class="flex flex-col space-y-2 text-center">
                <.link patch={@week} class="btn btn-sm border border-base-300 hover:btn-ghost w-full">{s(
                  @locale,
                  "last_7_days"
                )}</.link>
              </div>
            </div>
            <div class="w-full lg:w-2/12">
              <div class="flex flex-col space-y-2 text-center">
                <.link patch={@month} class="btn btn-sm border border-base-300 hover:btn-ghost w-full">{s(
                  @locale,
                  "last_month"
                )}</.link>
              </div>
            </div>
            <div class="w-full lg:w-1/12 relative">
              <a
                href={"/share_links/hub?" <> Plug.Conn.Query.encode(%{"end_date" => Date.to_iso8601(@window.end_date), "start_date" => Date.to_iso8601(@window.start_date)})}
                class="btn btn-sm border border-base-300 hover:btn-ghost w-full flex-nowrap"
                data-testid="timeline-share-button"
              >
                <Icon.icon name="share" class="w-4 h-4" />
                <span class="ml-1">{s(@locale, "share")}</span>
              </a>
              <span
                :if={@live_share}
                class="absolute -top-1 -right-1 w-2.5 h-2.5 bg-green-500 rounded-full animate-pulse ring-2 ring-base-100 pointer-events-none"
                data-testid="live-share-dot"
                title={t(@locale, "shared.map.share_indicator.live_location_is_being_shared", %{})}
              ></span>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "shared.map.date_navigation_v2." <> key, %{})
end
