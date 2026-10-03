defmodule DawarichWeb.SegmentRow do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Icon, SegmentFormat, TimeAgo, TimelineFormat}

  attr :segment, :map, required: true
  attr :user, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :unit, :string, required: true
  attr :now, DateTime, required: true

  def row(assigns) do
    assigns =
      assign(assigns, :percent, SegmentFormat.confidence(assigns.segment.confidence_score))

    ~H"""
    <turbo-frame
      id={"segment-row-#{@segment.id}"}
      class="segment-row flex items-center gap-2 py-1 text-sm"
      data-controller="segment-mode-editor"
      data-segment-mode-editor-segment-id-value={@segment.id}
      data-segment-mode-editor-track-id-value={@segment.track_id}
      data-segment-mode-editor-mode-value={@segment.transportation_mode || ""}
      data-action="mouseenter->segment-mode-editor#hover mouseleave->segment-mode-editor#unhover"
      data-testid={"segment-row-#{@segment.id}"}
    >
      <Icon.icon
        name={TimelineFormat.mode_icon(@segment.transportation_mode)}
        class="segment-row__icon"
      />
      <form
        class="contents"
        data-turbo-frame={"segment-row-#{@segment.id}"}
        action={"/tracks/#{@segment.track_id}/segments/#{@segment.id}"}
        accept-charset="UTF-8"
        method="post"
      >
        <input type="hidden" name="_method" value="patch" />
        <input type="hidden" name="authenticity_token" value={@csrf} />
        <label class="relative inline-flex items-center gap-0.5 shrink-0 cursor-pointer font-medium underline decoration-dotted underline-offset-4 decoration-base-content/25 hover:decoration-base-content/70 focus-within:decoration-base-content/70 transition-colors">
          <span>{t(@locale, "transportation_modes.#{@segment.transportation_mode}", %{})}</span>
          <span class="text-base-content/40 text-[10px] leading-none mt-px" aria-hidden="true">▾</span>
          <select
            class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
            aria-label={
              s(@locale, "transportation_mode_currently", %{
                mode: t(@locale, "transportation_modes.#{@segment.transportation_mode}", %{})
              })
            }
            data-action="change->segment-mode-editor#submit"
            data-testid={"segment-mode-select-#{@segment.id}"}
            name="track_segment[transportation_mode]"
            id="track_segment_transportation_mode"
          >
            <option
              :for={
                {label, value} <-
                  SegmentFormat.modes_for_mode(@segment.transportation_mode, @user, @locale)
              }
              selected={if value == @segment.transportation_mode, do: "selected"}
              value={value}
            >
              {label}
            </option>
          </select>
        </label>
        <span
          :if={@segment.corrected_at}
          class="shrink-0 text-info/80 leading-none"
          title={
            s(@locale, "edited_ago", %{time: TimeAgo.words(@locale, @segment.corrected_at, @now)})
          }
          aria-label={s(@locale, "manually_corrected")}
        >
          <Icon.icon name="square-pen" class="w-3 h-3" />
        </span>
        <span class="text-xs text-base-content/55 truncate min-w-0 tabular-nums" phx-no-format><span aria-hidden="true" class="opacity-40 mr-1">·</span>{SegmentFormat.segment_distance(@segment.distance, @unit, @locale)}<span aria-hidden="true" class="opacity-40 mx-1">·</span>{SegmentFormat.segment_duration(@segment.duration, @locale)}<span :if={@percent != nil and is_nil(@segment.corrected_at)} aria-hidden="true" class="opacity-40 mx-1">·</span><span :if={@percent != nil and is_nil(@segment.corrected_at)} title={s(@locale, "detection_confidence")}>{s(@locale, "confidence_percent", %{percent: @percent})}</span></span>
        <button
          :if={@segment.corrected_at}
          name="reset"
          value="true"
          type="submit"
          class="btn btn-ghost btn-xs btn-square shrink-0 ml-auto opacity-60 hover:opacity-100"
          title={s(@locale, "restore_auto_detection")}
          aria-label={s(@locale, "reset_to_auto_detected_mode")}
          data-testid={"segment-reset-#{@segment.id}"}
        >
          <Icon.icon name="rotate-ccw" class="w-3.5 h-3.5" />
        </button>
      </form>
    </turbo-frame>
    """
  end

  defp s(locale, key, bindings \\ %{}),
    do: t(locale, "tracks.segments.segment_row." <> key, bindings)
end
