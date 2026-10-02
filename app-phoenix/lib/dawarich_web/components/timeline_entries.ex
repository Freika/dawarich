defmodule DawarichWeb.TimelineEntries do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{Icon, LocalizedTime, TimelineFormat}

  @row_actions "click->timeline-feed#selectVisit keydown.enter->timeline-feed#selectVisit keydown.space->timeline-feed#selectVisit mouseenter->timeline-feed#entryHover mouseleave->timeline-feed#entryUnhover"

  attr :entry, :map, required: true
  attr :locale, :string, required: true
  attr :ctx, :map, required: true

  def visit_entry(assigns) do
    entry = assigns.entry
    gating = assigns.ctx.redetected
    coords = entry.place || entry.area || List.first(entry[:suggested_places] || [])
    all_day = TimelineFormat.all_day?(entry)
    name = TimelineFormat.display_name(entry, assigns.locale)
    start_label = LocalizedTime.l(assigns.locale, entry.start_local, "hour_minute")

    classes =
      Enum.join(
        ["visit-row"] ++
          if(all_day, do: ["visit-row--all-day"], else: []) ++
          if(TimelineFormat.subdued?(entry, gating), do: ["visit-row--subdued"], else: []) ++
          if(TimelineFormat.low_confidence?(entry, gating), do: ["visit-row--lowconf"], else: []),
        " "
      )

    assigns =
      assign(assigns,
        coords: coords,
        all_day: all_day,
        name: name,
        parts: TimelineFormat.name_parts(entry, assigns.locale),
        start_label: start_label,
        classes: classes,
        controllers: if(coords, do: "visit-editor visit-place-search", else: "visit-editor"),
        coord_attrs: coord_attrs(coords, entry, assigns.ctx),
        row_actions: @row_actions
      )

    ~H"""
    <li
      class={@classes}
      id={"visit_entry_#{@entry.visit_id}"}
      data-visit-id={@entry.visit_id}
      data-status={@entry.status || "confirmed"}
      data-confidence-band={@entry.confidence_band || ""}
      data-testid="visit-row"
      tabindex="0"
      role="button"
      aria-label={"#{@name} · #{@start_label}"}
      data-action={@row_actions}
      data-entry-type="visit"
      data-started-at={@entry.started_at}
      data-ended-at={@entry.ended_at}
      data-search-tokens={TimelineFormat.search_tokens(@entry)}
      data-controller={@controllers}
      {@coord_attrs}
    >
      <span class="visit-row__check">
        <input
          type="checkbox"
          data-timeline-feed-target="rowCheck"
          data-visit-id={@entry.visit_id}
          data-action="change->timeline-feed#rowCheckChanged click->timeline-feed#stopPropagation"
          aria-label={v(@locale, "select_visit_for_merge")}
          tabindex="-1"
        />
      </span>
      <div class="visit-row__time">
        <%= if @all_day do %>
          <span class="visit-row__all-day">{v(@locale, "all_day")}</span>
        <% else %>
          {@start_label}
        <% end %>
      </div>
      <div class="visit-row__rail">
        <span class="visit-status-dot"></span>
      </div>
      <div class="visit-row__content">
        <div class="visit-row__title">
          <span data-testid={"visit-name-#{@entry.visit_id}"}>{@parts.primary}</span>
        </div>
        <div class="visit-row__meta">
          <span :if={@parts.secondary} class="visit-row__address">{@parts.secondary}</span>
          <span class="visit-row__points">{@entry.point_count} {v(@locale, "pts")}</span>
          <span :for={tag <- @entry.tags} class="visit-tag">
            <span class="visit-tag__dot" style={"background-color: #{tag.color};"}></span>{"#" <>
              tag.name}
          </span>
        </div>
      </div>
      <div class="visit-row__actions">
        <button
          type="button"
          class="visit-edit-btn"
          data-testid="visit-edit"
          data-visit-editor-target="button"
          aria-expanded="false"
          title={v(@locale, "edit")}
          data-action="click->visit-editor#toggle"
        >
          <Icon.icon name="square-pen" class="w-3 h-3" />
          <span class="sr-only">{v(@locale, "edit")}</span>
        </button>
        <span :if={not @all_day} class="visit-row__duration">{TimelineFormat.dwell(
          @locale,
          @entry.duration
        )}</span>
      </div>
      <div
        class="visit-row__editor hidden"
        data-visit-editor-target="panel"
        data-action="click->timeline-feed#stopPropagation keydown->timeline-feed#stopPropagation"
      >
        <label class="visit-editor__label" for={"visit-editor-name-#{@entry.visit_id}"}>{v(
          @locale,
          "name"
        )}</label>
        <form
          class="visit-editor__name-form"
          action={"/visits/#{@entry.visit_id}"}
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="_method" value="patch" autocomplete="off" />
          <input type="hidden" name="authenticity_token" value={@ctx.csrf} autocomplete="off" />
          <input
            value={@name}
            id={"visit-editor-name-#{@entry.visit_id}"}
            class="input input-xs input-bordered flex-1 min-w-0"
            data-testid="visit-editor-name"
            type="text"
            name="visit[name]"
          />
          <input
            type="submit"
            name="commit"
            value={v(@locale, "save")}
            class="btn btn-xs btn-primary"
            data-testid="visit-editor-save"
            data-disable-with={v(@locale, "save")}
          />
        </form>
        <%= if @coords do %>
          <label class="visit-editor__label">{v(@locale, "attached_place")}</label>
          <div class="visit-row__place-search" data-visit-place-search-target="mount"></div>
        <% end %>
        <div class="visit-editor__foot">
          <form class="button_to" method="post" action={"/visits/#{@entry.visit_id}"}>
            <input type="hidden" name="_method" value="delete" autocomplete="off" />
            <button
              data-testid="visit-delete"
              data-turbo-confirm={v(@locale, "delete_this_visit_your_location_points_stay")}
              class="btn btn-xs btn-ghost text-error"
              type="submit"
            >
              {v(@locale, "delete")}
            </button>
            <input type="hidden" name="authenticity_token" value={@ctx.csrf} autocomplete="off" />
          </form>
        </div>
      </div>
    </li>
    """
  end

  defp coord_attrs(nil, _entry, _ctx), do: []

  defp coord_attrs(coords, entry, ctx),
    do: [
      {"data-visit-lat", Ruby.to_s(coords.lat)},
      {"data-visit-lng", Ruby.to_s(coords.lng)},
      {"data-visit-place-search-visit-id-value", entry.visit_id},
      {"data-visit-place-search-lat-value", Ruby.to_s(coords.lat)},
      {"data-visit-place-search-lng-value", Ruby.to_s(coords.lng)},
      {"data-visit-place-search-api-key-value", ctx.api_key}
    ]

  defp v(locale, key), do: t(locale, "map.timeline_feeds.visit_entry." <> key, %{})
end
