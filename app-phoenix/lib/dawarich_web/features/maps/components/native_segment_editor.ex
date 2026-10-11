defmodule DawarichWeb.NativeSegmentEditor do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, SegmentFormat, TimelineFormat}

  attr :drawer, :map, default: nil
  attr :locale, :string, required: true
  attr :unit, :string, default: "km"

  def drawer(%{drawer: nil} = assigns), do: ~H""

  def drawer(assigns) do
    assigns =
      assign(assigns, :mode_user, %{
        settings: %{"enabled_transportation_modes" => assigns.drawer.modes}
      })

    ~H"""
    <section id="native-segment-drawer" class="track-segments-list min-w-0" aria-live="polite">
      <p
        :if={Map.get(@drawer, :notice) == :updated and is_nil(@drawer.error)}
        role="status"
        class="text-sm [overflow-wrap:anywhere]"
      >
        {t(@locale, "controllers.tracks.segments.segment_updated", %{})}
      </p>
      <p :if={@drawer.error} class="alert alert-error text-sm" role="alert">
        {error(@locale, @drawer.error)}
      </p>
      <p :if={@drawer.segments == []} class="text-sm text-base-content/60">
        {t(@locale, "tracks.segments.index.no_segments_for_this_track_yet", %{})}
      </p>
      <div
        :for={segment <- @drawer.segments}
        id={"native-segment-#{segment.id}"}
        data-segment-id={segment.id}
        data-track-id={@drawer.track_id}
        class="flex flex-wrap items-center gap-2 py-1 text-sm"
      >
        <Icon.icon name={TimelineFormat.mode_icon(segment.transportation_mode)} class="w-4 h-4" />
        <form id={"native-segment-form-#{segment.id}"} phx-change="segment:mode" class="contents">
          <input type="hidden" name="segment_id" value={segment.id} />
          <select
            class="select select-xs select-bordered min-w-0"
            name="mode"
            aria-label={s(@locale, "transportation_mode_currently", %{mode: mode(@locale, segment)})}
          >
            <option
              :for={
                {label, value} <-
                  SegmentFormat.modes_for_mode(segment.transportation_mode, @mode_user, @locale)
              }
              value={value}
              selected={value == segment.transportation_mode}
            >
              {label}
            </option>
          </select>
        </form>
        <span :if={segment.corrected_at} data-corrected aria-label={s(@locale, "manually_corrected")}>
          <Icon.icon name="square-pen" class="w-3 h-3 text-info/80" />
        </span>
        <span class="text-xs text-base-content/55 min-w-0 tabular-nums">
          {SegmentFormat.segment_distance(segment.distance, @unit, @locale)} · {SegmentFormat.segment_duration(
            segment.duration,
            @locale
          )}
        </span>
        <button
          :if={segment.corrected_at}
          type="button"
          class="btn btn-ghost btn-xs btn-square ml-auto"
          phx-click="segment:reset"
          phx-value-segment_id={segment.id}
          aria-label={s(@locale, "reset_to_auto_detected_mode")}
        >
          <Icon.icon name="rotate-ccw" class="w-3.5 h-3.5" />
        </button>
      </div>
    </section>
    """
  end

  defp error(locale, code) when code in [:mode_not_enabled, :reprocess_failed],
    do: t(locale, "controllers.tracks.segments.#{code}", %{})

  defp error(locale, _code),
    do: t(locale, "controllers.tracks.segments.reprocess_failed", %{})

  defp mode(locale, segment),
    do: t(locale, "transportation_modes.#{segment.transportation_mode}", %{})

  defp s(locale, key, bindings \\ %{}),
    do: t(locale, "tracks.segments.segment_row." <> key, bindings)
end
