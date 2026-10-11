defmodule DawarichWeb.NativeTimelineEntries do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{Icon, LocalizedTime, TimelineFormat}

  attr :entry, :map, required: true
  attr :locale, :string, required: true
  attr :redetected, :boolean, default: false
  attr :selection, :any, default: nil

  def visit(assigns) do
    entry = assigns.entry

    assigns =
      assign(assigns,
        all_day: TimelineFormat.all_day?(entry),
        parts: TimelineFormat.name_parts(entry, assigns.locale),
        start_label: LocalizedTime.l(assigns.locale, entry.start_local, "hour_minute"),
        low: TimelineFormat.low_confidence?(entry, assigns.redetected),
        subdued: TimelineFormat.subdued?(entry, assigns.redetected)
      )

    ~H"""
    <li
      id={"native-visit-#{@entry.visit_id}"}
      class={[
        "visit-row min-w-0",
        @all_day && "visit-row--all-day",
        @subdued && "visit-row--subdued",
        @low && "visit-row--lowconf"
      ]}
      data-entry="visit"
      data-visit-id={@entry.visit_id}
      data-status={@entry.status || "confirmed"}
      data-confidence-band={@entry.confidence_band || ""}
      data-started-at={@entry.started_at}
      data-ended-at={@entry.ended_at}
    >
      <input
        :if={@selection}
        type="checkbox"
        class="checkbox checkbox-xs"
        checked={to_string(@entry.visit_id) in @selection}
        phx-click="timeline:select"
        phx-value-id={@entry.visit_id}
        aria-label={@parts.primary}
      />
      <div class="visit-row__time">
        {if @all_day, do: v(@locale, "all_day"), else: @start_label}
      </div>
      <div class="visit-row__rail"><span class="visit-status-dot"></span></div>
      <div class="visit-row__content min-w-0">
        <div class="visit-row__title [overflow-wrap:anywhere]">{@parts.primary}</div>
        <div class="visit-row__meta flex flex-wrap gap-1">
          <span :if={@parts.secondary} class="visit-row__address [overflow-wrap:anywhere]">{@parts.secondary}</span>
          <span class="visit-row__points">{@entry.point_count} {v(@locale, "pts")}</span>
          <span :for={tag <- @entry.tags} class="visit-tag">
            <span class="visit-tag__dot" style={"background-color: #{tag.color};"}></span>{"#" <>
              tag.name}
          </span>
        </div>
      </div>
      <div class="visit-row__actions flex flex-wrap gap-1">
        <button
          :if={@entry.status == "suggested"}
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="visit:status"
          phx-value-id={@entry.visit_id}
          phx-value-status="confirmed"
          aria-label={t(@locale, "javascript.common.confirm", %{})}
        >
          <Icon.icon name="circle-check" class="w-3.5 h-3.5" />
        </button>
        <button
          :if={@entry.status == "suggested"}
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="visit:status"
          phx-value-id={@entry.visit_id}
          phx-value-status="declined"
          aria-label={t(@locale, "javascript.common.decline", %{})}
        >
          <Icon.icon name="circle-x" class="w-3.5 h-3.5" />
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="visit:edit"
          phx-value-id={@entry.visit_id}
          aria-label={t(@locale, "javascript.visits.edit", %{})}
        >
          <Icon.icon name="square-pen" class="w-3.5 h-3.5" />
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="visit:delete"
          phx-value-id={@entry.visit_id}
          data-confirm={v(@locale, "delete_this_visit_your_location_points_stay")}
          aria-label={t(@locale, "javascript.common.delete", %{})}
        >
          <Icon.icon name="trash-2" class="w-3.5 h-3.5" />
        </button>
      </div>
    </li>
    """
  end

  attr :entry, :map, required: true
  attr :locale, :string, required: true

  def journey(assigns) do
    entry = assigns.entry
    mode = entry.dominant_mode || "unknown"

    assigns =
      assign(assigns,
        mode: mode,
        time: LocalizedTime.l(assigns.locale, entry.start_local, "hour_minute"),
        duration: TimelineFormat.duration_short(assigns.locale, entry.duration),
        distance:
          if(entry.distance > 0, do: "#{Ruby.to_s(entry.distance)} #{entry.distance_unit}")
      )

    ~H"""
    <li
      class="timeline-entry timeline-entry--journey min-w-0"
      data-entry="journey"
      data-track-id={@entry.track_id}
      data-started-at={@entry.started_at}
      data-ended-at={@entry.ended_at}
    >
      <button
        type="button"
        class="journey-leg w-full text-left"
        phx-click={@entry.track_id && "track:toggle"}
        phx-value-id={@entry.track_id}
        disabled={is_nil(@entry.track_id)}
      >
        <div class="journey-leg__time">{@time}</div>
        <div class="journey-leg__rail-col" aria-hidden="true"></div>
        <div class="journey-leg__summary flex flex-wrap gap-1">
          <Icon.icon name={TimelineFormat.mode_icon(@mode)} class="w-4 h-4" />
          <span class="journey-leg__verb">{t(@locale, "transportation_verbs.#{@mode}", %{})}</span>
          <span :if={@distance}>{@distance}</span>
          <span>{@duration}</span>
        </div>
      </button>
    </li>
    """
  end

  attr :entry, :map, required: true
  attr :locale, :string, required: true

  def gap(assigns) do
    ~H"""
    <li class="timeline-entry timeline-entry--gap" data-entry="gap">
      <div class="gap-leg">
        <div class="gap-leg__time">{LocalizedTime.l(@locale, @entry.start_local, "hour_minute")}</div>
        <div class="gap-leg__rail-col" aria-hidden="true"></div>
        <div class="gap-leg__summary">
          {t(@locale, "map.timeline_feeds.gap_entry.untracked", %{
            duration: TimelineFormat.duration_short(@locale, @entry.minutes * 60)
          })}
        </div>
      </div>
    </li>
    """
  end

  defp v(locale, key), do: t(locale, "map.timeline_feeds.visit_entry." <> key, %{})
end
