defmodule DawarichWeb.NativeTrackInfo do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Timeline.Days

  attr :track, :map, default: nil
  attr :unit, :string, default: "km"
  attr :locale, :string, required: true

  def card(%{track: nil} = assigns), do: ~H""

  def card(assigns) do
    assigns =
      assign(assigns,
        distance: Days.distance(assigns.track.distance, assigns.unit),
        speed: Days.speed(assigns.track.avg_speed || 0.0, assigns.unit),
        speed_label:
          t(
            assigns.locale,
            if(assigns.unit == "mi",
              do: "units.miles_per_hour",
              else: "units.kilometers_per_hour"
            ),
            %{}
          )
      )

    ~H"""
    <section
      id="native-track-info"
      data-track-id={@track.id}
      class="track-info-card min-w-0"
      aria-live="polite"
    >
      <div class="flex flex-wrap gap-2 items-center">
        <h3 class="track-info-card__id">{s(@locale, "track")}{@track.id}</h3>
        <button
          type="button"
          class="btn btn-xs"
          phx-click="track:close"
          aria-label={t(@locale, "javascript.common.close", %{})}
        >×</button>
      </div>
      <div class="track-info-stats flex flex-wrap gap-2 min-w-0">
        <span>{s(@locale, "dist")} <strong>{Ruby.to_s(@distance)} {@unit}</strong></span>
        <span>{s(@locale, "avg")} <strong>{Ruby.to_s(@speed)} {@speed_label}</strong></span>
        <span :if={(@track.elevation_gain || 0) > 0}>↑ {t(@locale, "units.meters", %{
          value: @track.elevation_gain
        })}</span>
        <span :if={(@track.elevation_loss || 0) > 0}>↓ {t(@locale, "units.meters", %{
          value: @track.elevation_loss
        })}</span>
        <span class="track-info-mode">{t(
          @locale,
          "transportation_modes.#{@track.mode || "unknown"}",
          %{}
        )}</span>
      </div>
      <div class="track-info-actions flex flex-wrap gap-2 min-w-0">
        <label class="flex items-center gap-2">
          <input
            type="checkbox"
            class="toggle toggle-xs"
            data-track-points
            checked={@track.points}
            phx-click="track:points"
          />
          <span>{s(@locale, "show_points")}</span>
        </label>
        <button
          type="button"
          class="btn btn-xs"
          data-track-replay
          data-track-start={@track.started_at}
        >{s(@locale, "replay")}</button>
        <button
          type="button"
          class="btn btn-xs"
          phx-click="segments:open"
          phx-value-track_id={@track.id}
        >{t(@locale, "map.maplibre.settings_panel.transportation_mode_detection", %{})}</button>
        <a href={"/tracks/#{@track.id}/share_link/new"} class="btn btn-xs">{s(@locale, "share")}</a>
      </div>
    </section>
    """
  end

  defp s(locale, key), do: t(locale, "map.timeline_feeds.track_info." <> key, %{})
end
