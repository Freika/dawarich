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
          class="btn btn-primary w-full max-w-96 min-w-0"
          phx-click={JS.toggle(to: "#native-map-date-panel")}
          aria-controls="native-map-date-panel"
        >
          <Icon.icon name="chevron-down" class="size-6" />
          <span class="ml-2 min-w-0">{human_date(@locale, @window.start_date)}</span>
        </button>
      </div>
      <div
        id="native-map-date-panel"
        class="hidden lg:!block bg-base-100 rounded-lg p-4 mt-2 lg:mt-0 container mx-auto"
      >
        <form
          id="native-map-dates"
          phx-submit="map:dates"
          class="flex flex-col gap-2 lg:flex-row lg:flex-wrap lg:items-center"
        >
          <.link
            id="native-map-prev-day"
            patch={@prev}
            class="btn btn-sm border border-base-300 hover:btn-ghost"
            aria-label={human_date(@locale, @window.prev_date)}
          >
            <Icon.icon name="chevron-left" class="size-6" />
          </.link>
          <label class="min-w-0 lg:w-48">
            <span class="sr-only">{s(@locale, "start_date_and_time")}</span>
            <input
              max="9999-12-31T23:59"
              class="input input-sm input-bordered w-full"
              type="datetime-local"
              value={@window.start_local}
              name="start_at"
            />
          </label>
          <label class="min-w-0 lg:w-48">
            <span class="sr-only">{s(@locale, "end_date_and_time")}</span>
            <input
              max="9999-12-31T23:59"
              class="input input-sm input-bordered w-full"
              type="datetime-local"
              value={@window.end_local}
              name="end_at"
            />
          </label>
          <.link
            id="native-map-next-day"
            patch={@next}
            class="btn btn-sm border border-base-300 hover:btn-ghost"
            aria-label={human_date(@locale, @window.next_date)}
          >
            <Icon.icon name="chevron-right" class="size-6" />
          </.link>
          <a
            href={"/share_links/hub?" <> Plug.Conn.Query.encode(%{"start_date" => Date.to_iso8601(@window.start_date), "end_date" => Date.to_iso8601(@window.end_date), "locale" => @locale})}
            data-testid="timeline-share-button"
            class="btn btn-sm h-auto whitespace-normal"
          >{t(@locale, "share_links.hubs.frame.share", %{})}</a>
          <button type="submit" class="btn btn-sm btn-primary">{s(@locale, "search")}</button>
          <.link id="native-map-today" patch={@today} class="btn btn-sm border border-base-300">{s(
            @locale,
            "today"
          )}</.link>
          <.link patch={@week} class="btn btn-sm border border-base-300">{s(@locale, "last_7_days")}</.link>
          <.link patch={@month} class="btn btn-sm border border-base-300">{s(@locale, "last_month")}</.link>
        </form>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "shared.map.date_navigation_v2." <> key, %{})
end
