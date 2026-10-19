defmodule DawarichWeb.NativeMapSettingsTabMore do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  @badge "badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center"

  attr :locale, :string, required: true
  attr :settings, :map, default: nil
  attr :saved, :map, required: true
  attr :csrf_token, :string, default: nil

  def sections(assigns) do
    saved_modes = assigns.saved["enabled_transportation_modes"] || []
    modes = (assigns.settings && assigns.settings.draft_modes) || saved_modes
    dirty = (assigns.settings && assigns.settings[:dirty]) || %{}

    assigns =
      assign(assigns,
        modes: Dawarich.Settings.Api.modes(),
        chosen: modes,
        transport_dirty: Enum.sort(modes) != Enum.sort(saved_modes),
        dirty: dirty,
        radius: assigns.saved["fog_of_war_meters"] |> int(1000) |> clamp(5, 2000),
        threshold: assigns.saved["fog_of_war_threshold"] |> int(1) |> clamp(1, 10),
        city: assigns.saved["min_minutes_spent_in_city"] |> int(60) |> clamp(5, 120)
      )

    ~H"""
    <.section
      icon="route"
      title={p(@locale, "track_generation")}
      dirty={@dirty["track"]}
      locale={@locale}
    >
      <.number
        id="meters-between-routes"
        name="metersBetweenRoutes"
        label={p(@locale, "track_split_distance")}
        unit={p(@locale, "track_split_distance_unit")}
        hint={p(@locale, "track_split_distance_hint")}
        value={@saved["meters_between_routes"] || "500"}
      />
      <.number
        id="minutes-between-routes"
        name="minutesBetweenRoutes"
        max="1440"
        label={p(@locale, "track_split_time")}
        unit={p(@locale, "track_split_time_unit")}
        hint={p(@locale, "track_split_time_hint")}
        value={@saved["minutes_between_routes"] || "30"}
      />
      <button type="button" class="btn btn-sm btn-outline btn-block" phx-click="settings:recalculate">
        <Icon.icon name="refresh-ccw" class="size-6" />
        {p(@locale, "recalculate_tracks_stats")}
      </button>
      <p class="text-xs text-base-content/60">
        {p(
          @locale,
          "rebuild_tracks_stats_and_digests_from_your_current_points_without"
        )}
      </p>
    </.section>

    <.section icon="cloud-fog" title={p(@locale, "fog_of_war")} dirty={@dirty["fog"]} locale={@locale}>
      <.range
        name="fogOfWarRadius"
        label={p(@locale, "fog_of_war_radius")}
        shown={meters(@locale, @radius)}
        min="5"
        max="2000"
        step="5"
        value={@radius}
        marks={[meters(@locale, 5), meters(@locale, 1000), meters(@locale, 2000)]}
        hint={p(@locale, "clear_radius_around_visited_points")}
      />
      <.range
        name="fogOfWarThreshold"
        label={p(@locale, "fog_of_war_threshold")}
        shown={to_string(@threshold)}
        min="1"
        max="10"
        step="1"
        value={@threshold}
        marks={["1", "5", "10"]}
        hint={p(@locale, "minimum_points_to_clear_fog")}
      />
    </.section>

    <.section
      icon="satellite"
      title={p(@locale, "gps_noise_filtering")}
      dirty={@dirty["gps"]}
      locale={@locale}
    >
      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-3">
          <input
            type="checkbox"
            name="gpsFilteringEnabled"
            class="toggle toggle-primary"
            checked={@saved["gps_filtering_enabled"] != false}
          />
          <span class="label-text font-medium">{p(@locale, "gps_noise_filtering")}</span>
        </label>
        <p class="text-sm text-base-content/60 mt-1">
          {p(
            @locale,
            "hide_readings_that_cannot_be_a_real_position_impossible_jumps"
          )}
        </p>
      </div>
      <button
        type="button"
        class="btn btn-sm btn-outline btn-block"
        phx-click="settings:reapply_anomalies"
      >
        <Icon.icon name="rotate-ccw" class="size-6" />
        {p(@locale, "re_evaluate_past_data")}
      </button>
      <p class="text-xs text-base-content/60 mt-1">
        {p(
          @locale,
          "clears_existing_anomaly_flags_and_re_runs_the_filter_on"
        )}
      </p>
    </.section>

    <.section
      icon="chart-column"
      title={p(@locale, "city_statistics")}
      dirty={@dirty["city"]}
      locale={@locale}
    >
      <.range
        name="minMinutesSpentInCity"
        label={p(@locale, "min_minutes_in_city")}
        shown={"#{@city} min"}
        min="5"
        max="120"
        step="5"
        value={@city}
        marks={[p(@locale, "min_6"), p(@locale, "min"), p(@locale, "min_7")]}
        hint={p(@locale, "how_long_you_must_stay_for_a_city_to_count")}
      />
    </.section>

    <details class="collapse collapse-arrow bg-base-200 rounded-lg" phx-mounted={keep_open()}>
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="radio" class="h-4 w-4 opacity-70 shrink-0" />
          {p(@locale, "live_mode")}
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              checked={@saved["live_map_enabled"] != false}
              phx-click="settings:live"
              data-map-live-toggle
              phx-value-enabled={to_string(@saved["live_map_enabled"] == false)}
            />
            <span class="label-text font-medium">{p(@locale, "live_mode")}</span>
          </label>
          <p class="text-sm text-base-content/60 mt-1">
            {p(@locale, "show_new_points_in_real_time")}
          </p>
        </div>
      </div>
    </details>

    <button type="submit" class="btn btn-sm btn-primary btn-block">
      <Icon.icon name="save" class="size-6" />
      {p(@locale, "apply_settings")}
    </button>

    <button
      type="button"
      class="btn btn-sm btn-outline btn-block"
      phx-click="settings:reset"
      data-confirm={t(@locale, "javascript.settings.confirm_reset", %{})}
    >
      <Icon.icon name="rotate-ccw" class="size-6" />
      {p(@locale, "reset_to_defaults_2")}
    </button>

    <div class="divider"></div>

    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-dirty-scope="transportation"
      phx-mounted={keep_open()}
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="car" class="h-4 w-4 opacity-70 shrink-0" />
          {p(@locale, "transportation_mode_detection")}
          <.dirty_badge fields={@dirty["transportation"]} locale={@locale} />
        </span>
      </summary>
      <div class="collapse-content">
        <div role="alert" class="text-xs text-warning bg-warning/10 rounded p-2 mb-4 hidden">
          <span class="loading loading-spinner loading-xs"></span>
          <span>{p(@locale, "checking_status")}</span>
        </div>

        <div role="alert" class="text-xs text-info bg-info/10 rounded p-2 mb-4 hidden">
          <span>{p(@locale, "settings_are_locked_while_recalculation_is_in_progress")}</span>
        </div>

        <div class="text-xs text-warning bg-warning/10 rounded p-2 mb-4">
          <strong>{p(@locale, "note")}</strong> {p(
            @locale,
            "changing_these_thresholds_will_trigger_a_recalculation_of_transportation"
          )}
        </div>

        <fieldset class="form-control mb-4" data-testid="enabled-modes-fieldset">
          <legend class="font-medium mb-1 text-sm">{p(@locale, "detected_modes")}</legend>
          <p class="text-xs text-base-content/60 mb-2">
            {p(@locale, "disabled_modes_won_t_be_detected_existing_tracks_aren_t")}
          </p>
          <div class="grid grid-cols-2 gap-1">
            <label :for={mode <- @modes} class="cursor-pointer label justify-start gap-2 py-0.5">
              <input
                type="checkbox"
                name="enabledTransportationModes[]"
                value={mode}
                class="checkbox checkbox-sm"
                checked={mode in @chosen}
                data-testid={"enabled-mode-#{mode}"}
              />
              <span class="text-sm">
                {mode_emoji(mode)} {t(@locale, "transportation_modes.#{mode}", %{})}
              </span>
            </label>
          </div>
        </fieldset>

        <div class="mt-4 pt-4 border-t border-base-300">
          <button
            id="native-transport-apply"
            type="button"
            class="btn btn-primary btn-sm w-full"
            disabled={!@transport_dirty}
            phx-click="settings:transport_apply"
            data-confirm={t(@locale, "javascript.settings.confirm_transportation_recalculation", %{})}
          >
            {p(@locale, "apply_settings")}
          </button>
          <p class="text-xs text-base-content/60 mt-2 text-center">
            {if @transport_dirty,
              do: t(@locale, "javascript.settings.unsaved_transportation_changes", %{}),
              else: p(@locale, "make_changes_to_enable_the_apply_button")}
          </p>
        </div>

        <div class="mt-4 pt-4 border-t border-base-300">
          <button
            class="btn btn-secondary btn-sm w-full"
            data-testid="reclassify-history-button"
            type="submit"
            form="native-reclassify"
          >{p(@locale, "re_classify_my_history")}</button><input
            type="hidden"
            name="authenticity_token"
            value={@csrf_token || ""}
            form="native-reclassify"
          />
          <p class="text-xs text-base-content/60 mt-1">
            {p(@locale, "re_runs_auto_classification_across_all_your_tracks_manually_corrected")}
          </p>
        </div>
      </div>
    </details>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :dirty, :list, default: nil
  attr :locale, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <details class="collapse collapse-arrow bg-base-200 rounded-lg" phx-mounted={keep_open()}>
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name={@icon} class="h-4 w-4 opacity-70 shrink-0" />
          {@title}
          <.dirty_badge fields={@dirty} locale={@locale} />
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :fields, :list, default: nil
  attr :locale, :string, required: true

  defp dirty_badge(assigns) do
    assigns = assign(assigns, :class, @badge)

    ~H"""
    <span
      :if={@fields in [nil, []]}
      class={@class <> " hidden"}
      data-dirty-badge
    ></span>
    <span
      :if={@fields not in [nil, []]}
      class={@class}
      data-dirty-badge
      data-tip={
        t(@locale, "javascript.settings.changed_fields", %{"fields" => Enum.join(@fields, ", ")})
      }
    >{t(@locale, "javascript.settings.unsaved_count", %{"count" => length(@fields)})}</span>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :unit, :string, required: true
  attr :hint, :string, required: true
  attr :value, :any, required: true
  attr :max, :string, default: nil

  defp number(assigns) do
    ~H"""
    <div class="form-control w-full">
      <label class="label" for={@id}>
        <span class="label-text font-medium">{@label}</span>
      </label>
      <label class="input input-bordered flex items-center gap-2">
        <input
          type="number"
          id={@id}
          name={@name}
          aria-label={@label}
          min="1"
          max={@max}
          step="1"
          value={@value}
          required
          class="grow"
        />
        <span class="text-base-content/60">{@unit}</span>
      </label>
      <p class="text-xs text-base-content/60 mt-1">{@hint}</p>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :shown, :string, required: true
  attr :min, :string, required: true
  attr :max, :string, required: true
  attr :step, :string, required: true
  attr :value, :any, required: true
  attr :marks, :list, required: true
  attr :hint, :string, required: true

  defp range(assigns) do
    ~H"""
    <div class="form-control w-full">
      <label class="label">
        <span class="label-text font-medium">{@label}</span>
        <span class="label-text-alt">{@shown}</span>
      </label>
      <input
        type="range"
        name={@name}
        aria-label={@label}
        min={@min}
        max={@max}
        step={@step}
        value={@value}
        class="range range-sm"
      />
      <div class="w-full flex justify-between text-xs px-2 mt-1">
        <span :for={mark <- @marks}>{mark}</span>
      </div>
      <p class="text-xs text-base-content/60 mt-1">{@hint}</p>
    </div>
    """
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp int(value, _default) when is_integer(value), do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      :error -> default
    end
  end

  defp int(_value, default), do: default

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
    "motorcycle" => "🏍️"
  }

  defp mode_emoji(mode), do: Map.get(@emoji, mode, "❓")

  defp meters(locale, value), do: t(locale, "units.meters_compact", %{"value" => value})
  defp keep_open, do: Phoenix.LiveView.JS.ignore_attributes(["open"])
  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
