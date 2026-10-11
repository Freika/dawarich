defmodule DawarichWeb.TimelineJourney do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{Icon, LocalizedDate, LocalizedTime, TimelineCalendar, TimelineFormat}

  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  attr :entry, :map, required: true
  attr :locale, :string, required: true

  def journey_entry(assigns) do
    entry = assigns.entry
    locale = assigns.locale
    mode = if entry.dominant_mode in @modes, do: entry.dominant_mode, else: "unknown"

    {leg_time, verb, duration, distance_text} =
      if entry.continuation_of_date do
        day_distance = entry.day_distance || entry.distance
        date = Date.from_iso8601!(entry.continuation_of_date)

        {LocalizedTime.l(locale, entry.end_local, "hour_minute"),
         j(locale, "continued_from_date_arrived", %{
           date: LocalizedDate.l(locale, date, "short_month_day")
         }), TimelineFormat.duration_short(locale, entry.day_duration || entry.duration),
         if(day_distance > 0,
           do:
             "#{Ruby.to_s(day_distance)} #{entry.distance_unit} of #{Ruby.to_s(entry.distance)} #{entry.distance_unit}"
         )}
      else
        moving = entry.moving_duration || 0

        duration =
          if moving > 0 and moving < (entry.duration || 0) * 0.8,
            do:
              j(locale, "duration_moving", %{
                duration: TimelineFormat.duration_short(locale, moving)
              }),
            else: TimelineFormat.duration_short(locale, entry.duration)

        {LocalizedTime.l(locale, entry.start_local, "hour_minute"),
         t(locale, "transportation_verbs.#{mode}", %{}), duration,
         if(entry.distance > 0, do: "#{Ruby.to_s(entry.distance)} #{entry.distance_unit}")}
      end

    assigns =
      assign(assigns,
        leg_time: leg_time,
        verb: verb,
        duration: duration,
        distance_text: distance_text,
        frame_id: "track-info-#{entry.track_id}",
        leg_extra: TimelineFormat.leg_extra(entry.day_duration || entry.duration)
      )

    ~H"""
    <div
      class="timeline-entry timeline-entry--journey"
      style={"--tl-leg-extra: #{@leg_extra}px"}
      data-action="mouseenter->timeline-feed#entryHover mouseleave->timeline-feed#entryUnhover"
      data-entry-type="journey"
      data-started-at={@entry.started_at}
      data-ended-at={@entry.ended_at}
      data-track-id={@entry.track_id}
    >
      <div
        class="journey-leg cursor-pointer"
        data-action="click->timeline-feed#toggleTrackInfo"
        data-track-id={@entry.track_id}
        data-frame-id={@frame_id}
        data-track-start={@entry.started_at}
      >
        <div class="journey-leg__time">{@leg_time}</div>
        <div class="journey-leg__rail-col" aria-hidden="true"></div>
        <div class="journey-leg__summary">
          <span class="journey-leg__verb">{@verb}</span>
          <%= if @distance_text do %>
            <span class="journey-leg__sep">{j(@locale, "middot")}</span>
            <span>{@distance_text}</span>
          <% end %>
          <span class="journey-leg__sep">{j(@locale, "middot")}</span>
          <span>{@duration}</span>
        </div>
        <Icon.icon name="chevron-down" class="journey-leg__chevron track-info-chevron" />
      </div>
      <turbo-frame
        id={@frame_id}
        class="hidden track-info-panel"
        data-timeline-feed-target="trackInfoFrame"
        loading="lazy"
      >
        <TimelineCalendar.skeleton lines={3} />
      </turbo-frame>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :locale, :string, required: true

  def gap_entry(assigns) do
    ~H"""
    <div
      class="timeline-entry timeline-entry--gap"
      style={"--tl-leg-extra: #{TimelineFormat.leg_extra(@entry.minutes * 60)}px"}
      data-entry-type="gap"
    >
      <div class="gap-leg">
        <div class="gap-leg__time">{LocalizedTime.l(@locale, @entry.start_local, "hour_minute")}</div>
        <div class="gap-leg__rail-col" aria-hidden="true"></div>
        <div class="gap-leg__summary">
          {t(@locale, "map.timeline_feeds.gap_entry.untracked", %{
            duration: TimelineFormat.duration_short(@locale, @entry.minutes * 60)
          })}
        </div>
        <span></span>
      </div>
    </div>
    """
  end

  defp j(locale, key, bindings \\ %{}),
    do: t(locale, "map.timeline_feeds.journey_entry." <> key, bindings)
end
