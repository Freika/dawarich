defmodule DawarichWeb.MapSettingsMore do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.MapPage
  alias DawarichWeb.Icon

  @emoji %{
    "unknown" => "❓",
    "stationary" => "🛑",
    "walking" => "🚶",
    "running" => "🏃",
    "cycling" => "🚴",
    "driving" => "🚗",
    "bus" => "🚌",
    "train" => "🚆",
    "flying" => "✈️",
    "boat" => "⛵",
    "motorcycle" => "\u{1F3CD}️"
  }

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, default: nil

  def more_settings(assigns) do
    ~H"""
    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-map-settings-dirty-target="section"
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="satellite" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "gps_noise_filtering")}
          <span
            class="badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center hidden"
            data-dirty-badge
          ></span>
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              name="gpsFilteringEnabled"
              class="toggle toggle-primary"
              data-maps--maplibre-target="gpsFilteringToggle"
            />
            <span class="label-text font-medium">{s(@locale, "gps_noise_filtering")}</span>
          </label>
          <p class="text-sm text-base-content/60 mt-1">
            {s(@locale, "hide_readings_that_cannot_be_a_real_position_impossible_jumps")}
          </p>
        </div>

        <button
          type="button"
          class="btn btn-sm btn-outline btn-block"
          data-action="click->maps--maplibre#reapplyAnomalyFilter"
        >
          <Icon.icon name="rotate-ccw" class="size-6" />
          {s(@locale, "re_evaluate_past_data")}
        </button>
        <p class="text-xs text-base-content/60 mt-1">
          {s(@locale, "clears_existing_anomaly_flags_and_re_runs_the_filter_on")}
        </p>
      </div>
    </details>

    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-map-settings-dirty-target="section"
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="chart-column" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "city_statistics")}
          <span
            class="badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center hidden"
            data-dirty-badge
          ></span>
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-medium">{s(@locale, "min_minutes_in_city")}</span>
            <span class="label-text-alt" data-maps--maplibre-target="minMinutesInCityValue">{s(
              @locale,
              "min_5"
            )}</span>
          </label>
          <input
            type="range"
            name="minMinutesSpentInCity"
            min="5"
            max="120"
            step="5"
            value="60"
            class="range range-sm"
            data-action="input->maps--maplibre#updateMinMinutesInCityDisplay"
          />
          <div class="w-full flex justify-between text-xs px-2 mt-1">
            <span>{s(@locale, "min_6")}</span>
            <span>{s(@locale, "min")}</span>
            <span>{s(@locale, "min_7")}</span>
          </div>
          <p class="text-xs text-base-content/60 mt-1">
            {s(@locale, "how_long_you_must_stay_for_a_city_to_count")}
          </p>
        </div>
      </div>
    </details>

    <details class="collapse collapse-arrow bg-base-200 rounded-lg">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="radio" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "live_mode")}
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              data-action="change->maps--maplibre-realtime#toggleLiveMode"
              data-maps--maplibre-realtime-target="liveModeToggle"
            />
            <span class="label-text font-medium">{s(@locale, "live_mode")}</span>
          </label>
          <p class="text-sm text-base-content/60 mt-1">
            {s(@locale, "show_new_points_in_real_time")}
          </p>
        </div>
      </div>
    </details>

    <button type="submit" class="btn btn-sm btn-primary btn-block">
      <Icon.icon name="save" class="size-6" />
      {s(@locale, "apply_settings")}
    </button>

    <button
      type="button"
      class="btn btn-sm btn-outline btn-block"
      data-action="click->maps--maplibre#resetSettings"
    >
      <Icon.icon name="rotate-ccw" class="size-6" />
      {s(@locale, "reset_to_defaults_2")}
    </button>

    <div class="divider"></div>

    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-map-settings-dirty-target="section"
      data-dirty-scope="transportation"
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="car" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "transportation_mode_detection")}
          <span
            class="badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center hidden"
            data-dirty-badge
          ></span>
        </span>
      </summary>
      <div class="collapse-content">
        <div
          role="alert"
          class="text-xs text-warning bg-warning/10 rounded p-2 mb-4 hidden"
          data-maps--maplibre-target="transportationRecalculationAlert"
        >
          <span class="loading loading-spinner loading-xs"></span>
          <span>{s(@locale, "checking_status")}</span>
        </div>

        <div
          role="alert"
          class="text-xs text-info bg-info/10 rounded p-2 mb-4 hidden"
          data-maps--maplibre-target="transportationLockedMessage"
        >
          <span>{s(@locale, "settings_are_locked_while_recalculation_is_in_progress")}</span>
        </div>

        <div class="text-xs text-warning bg-warning/10 rounded p-2 mb-4">
          <strong>{s(@locale, "note")}</strong>
          {s(@locale, "changing_these_thresholds_will_trigger_a_recalculation_of_transportation")}
        </div>

        <fieldset class="form-control mb-4" data-testid="enabled-modes-fieldset">
          <legend class="font-medium mb-1 text-sm">{s(@locale, "detected_modes")}</legend>
          <p class="text-xs text-base-content/60 mb-2">
            {s(@locale, "disabled_modes_won_t_be_detected_existing_tracks_aren_t")}
          </p>
          <div class="grid grid-cols-2 gap-1">
            <label
              :for={mode <- MapPage.modes()}
              class="cursor-pointer label justify-start gap-2 py-0.5"
            >
              <input
                type="checkbox"
                name="enabledTransportationModes[]"
                value={mode}
                class="checkbox checkbox-sm"
                checked={mode in @page.transport_modes}
                data-maps--maplibre-target="enabledModeCheckbox"
                data-action="change->maps--maplibre#markTransportationSettingsDirty"
                data-testid={"enabled-mode-#{mode}"}
              />
              <span class="text-sm">{mode_emoji(mode)} {t(
                @locale,
                "transportation_modes.#{mode}",
                %{}
              )}</span>
            </label>
          </div>
        </fieldset>

        <div class="mt-4 pt-4 border-t border-base-300">
          <button
            type="button"
            class="btn btn-primary btn-sm w-full"
            data-maps--maplibre-target="transportationApplyButton"
            data-action="click->maps--maplibre#applyTransportationSettings"
            disabled
          >
            {s(@locale, "apply_settings")}
          </button>
          <p
            class="text-xs text-base-content/60 mt-2 text-center"
            data-maps--maplibre-target="transportationDirtyMessage"
          >
            {s(@locale, "make_changes_to_enable_the_apply_button")}
          </p>
        </div>

        <div class="mt-4 pt-4 border-t border-base-300">
          <form class="button_to" method="post" action="/tracks/recalculation" data-turbo-frame="_top">
            <button
              class="btn btn-secondary btn-sm w-full"
              data-testid="reclassify-history-button"
              type="submit"
            >{s(
              @locale,
              "re_classify_my_history"
            )}</button><input
              :if={@rails_csrf_token}
              type="hidden"
              name="authenticity_token"
              value={@rails_csrf_token}
            />
          </form>
          <p class="text-xs text-base-content/60 mt-1">
            {s(@locale, "re_runs_auto_classification_across_all_your_tracks_manually_corrected")}
          </p>
        </div>
      </div>
    </details>
    """
  end

  defp mode_emoji(mode), do: Map.get(@emoji, mode, "❓")

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
