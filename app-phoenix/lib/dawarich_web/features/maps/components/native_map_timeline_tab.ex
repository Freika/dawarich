defmodule DawarichWeb.NativeMapTimelineTab do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :open, :boolean, required: true
  attr :calendar, :any, default: nil
  attr :timeline, :any, default: nil
  attr :filter, :any, default: nil
  attr :selection, :any, default: nil
  attr :selected_visit, :any, default: nil
  attr :selected_date, :string, default: nil
  attr :tags, :list, default: []
  attr :track_info, :any, default: nil
  attr :unit, :string, default: "km"

  def tab(assigns) do
    active = (assigns.filter || %{})["tags"] || []
    assigns = assign(assigns, active: active, query: (assigns.filter || %{})["q"])

    ~H"""
    <div class={["tab-content", @open && "active"]} data-tab-content="timeline-feed">
      <div class="timeline-tab-content" {if(@open, do: [id: "native-map-panel"], else: [])}>
        <aside class="timeline-rail">
          <DawarichWeb.NativeTimelineCalendar.calendar
            :if={@open && @calendar}
            calendar={@calendar}
            locale={@locale}
            selected_date={@selected_date}
          />
          <div :if={!(@open && @calendar)} class="text-center text-base-content/60 py-4 text-sm">
            {p(
              @locale,
              "loading_calendar"
            )}
          </div>

          <div class="timeline-rail__heat-legend">
            <span>{p(@locale, "less")}</span>
            <span :for={level <- 0..5} class={"heat-swatch heat-#{level}"}></span>
            <span>{p(@locale, "more")}</span>
          </div>

          <div class="relative">
            <Icon.icon
              name="search"
              class="h-4 w-4 opacity-50 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none"
            />
            <input
              type="text"
              placeholder={p(@locale, "search_visits_places")}
              aria-label={p(@locale, "search_visits_places")}
              class="input input-sm input-bordered w-full pl-8"
              autocomplete="off"
              form="native-timeline-filter"
              name="q"
              value={@query}
              phx-debounce="200"
            />
          </div>

          <div :if={@tags != []} class="timeline-rail__section">
            <div class="timeline-rail__section-header">
              <span class="timeline-rail__section-label">{p(@locale, "tags")}</span>
              <a
                class="timeline-rail__section-link"
                target="_blank"
                rel="noopener"
                title={p(@locale, "manage_tags_in_a_new_tab")}
                data-testid="tags-manage-link"
                href="/tags"
              >{p(@locale, "manage")}</a>
            </div>
            <div class="timeline-rail__tags">
              <button
                :for={tag <- @tags}
                type="button"
                class={[
                  "tag-chip tag-chip--toggle",
                  String.downcase(tag.name) in @active && "tag-chip--active"
                ]}
                data-tag-name={String.downcase(tag.name)}
                {if(tag.color in [nil, ""], do: [], else: [style: "background-color: #{tag.color};"])}
                aria-pressed={to_string(String.downcase(tag.name) in @active)}
                phx-click="timeline:tag"
                phx-value-tag={tag.name}
              >
                {if tag.icon not in [nil, ""], do: "#{tag.icon} "}{tag.name}
              </button>
            </div>
          </div>
        </aside>

        <div class="timeline-main">
          <%= if @open && @timeline do %>
            <DawarichWeb.NativeTimelineFeed.feed
              timeline={@timeline}
              selected_date={@selected_date}
              filter={@filter}
              selection={@selection}
              selected_visit={@selected_visit}
              locale={@locale}
            />
            <DawarichWeb.NativeTrackInfo.card track={@track_info} unit={@unit} locale={@locale} />
          <% else %>
            <div class="timeline-main__empty">
              {p(@locale, "pick_a_day_in_the_calendar_to_see_visits")}
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
