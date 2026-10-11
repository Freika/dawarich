defmodule DawarichWeb.MapTimelineTab do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.Icon

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :timeline, :boolean, required: true

  def timeline_tab(assigns) do
    ~H"""
    <div
      class={"tab-content#{if @timeline, do: " active"}"}
      data-tab-content="timeline-feed"
      data-map-panel-target="tabContent"
    >
      <div class="timeline-tab-content" data-controller="timeline-feed">
        <aside class="timeline-rail">
          <turbo-frame
            id="timeline-calendar-frame"
            src={"/map/timeline_feeds/calendar?month=#{@page.window.calendar_month}"}
            loading="lazy"
          >
            <div class="text-center text-base-content/60 py-4 text-sm">
              {s(@locale, "loading_calendar")}
            </div>
          </turbo-frame>
          <div class="timeline-rail__heat-legend">
            <span>{s(@locale, "less")}</span>
            <span :for={level <- 0..5} class={"heat-swatch heat-#{level}"}></span>
            <span>{s(@locale, "more")}</span>
          </div>
          <div class="relative">
            <Icon.icon
              name="search"
              class="h-4 w-4 opacity-50 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none"
            />
            <input
              type="text"
              placeholder={s(@locale, "search_visits_places")}
              class="input input-sm input-bordered w-full pl-8"
              autocomplete="off"
              data-timeline-feed-target="searchInput"
              data-action="input->timeline-feed#search"
            />
          </div>
          <div :if={@page.timeline_tags != []} class="timeline-rail__section">
            <div class="timeline-rail__section-header">
              <span class="timeline-rail__section-label">{s(@locale, "tags")}</span>
              <a
                class="timeline-rail__section-link"
                target="_blank"
                rel="noopener"
                title={s(@locale, "manage_tags_in_a_new_tab")}
                data-testid="tags-manage-link"
                href="/tags"
              >{s(@locale, "manage")}</a>
            </div>
            <div class="timeline-rail__tags">
              <button
                :for={tag <- @page.timeline_tags}
                type="button"
                class="tag-chip tag-chip--toggle"
                data-tag-name={String.downcase(tag.name)}
                data-action="click->timeline-feed#toggleTag"
                {color_style(tag.color)}
                aria-pressed="false"
              >
                {if Ruby.present?(tag.icon), do: "#{tag.icon} "}{tag.name}
              </button>
            </div>
          </div>
        </aside>
        <div class="timeline-main">
          <turbo-frame
            id="timeline-feed-frame"
            data-timeline-feed-target="visitListFrame"
            data-maps--maplibre-target="timelineFeedContainer"
          >
            <div class="timeline-main__empty">
              {s(@locale, "pick_a_day_in_the_calendar_to_see_visits")}
            </div>
          </turbo-frame>
        </div>
      </div>
    </div>
    """
  end

  defp color_style(color),
    do: if(Ruby.present?(color), do: [{"style", "background-color: #{color};"}], else: [])

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
