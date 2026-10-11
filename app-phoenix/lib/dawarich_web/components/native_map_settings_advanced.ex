defmodule DawarichWeb.NativeMapSettingsAdvanced do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  attr :saved, :map, required: true
  attr :locale, :string, required: true

  def advanced(assigns) do
    ~H"""
    <form id="native-advanced-form" phx-submit="settings:advanced" class="space-y-3">
      <.number
        name="meters_between_routes"
        label={p(@locale, "track_split_distance")}
        value={@saved["meters_between_routes"]}
        min="1"
        step="1"
      />
      <.number
        name="minutes_between_routes"
        label={p(@locale, "track_split_time")}
        value={@saved["minutes_between_routes"]}
        min="1"
        max="1440"
        step="1"
      />
      <.number
        name="fog_of_war_meters"
        label={p(@locale, "fog_of_war_radius")}
        value={@saved["fog_of_war_meters"]}
        min="5"
        max="2000"
        step="5"
      />
      <.number
        name="fog_of_war_threshold"
        type="range"
        label={p(@locale, "fog_of_war_threshold")}
        value={@saved["fog_of_war_threshold"]}
        min="1"
        max="10"
        step="1"
      />
      <.number
        name="min_minutes_spent_in_city"
        label={p(@locale, "min_minutes_in_city")}
        value={@saved["min_minutes_spent_in_city"]}
        min="5"
        max="120"
        step="5"
      />
      <.toggle
        name="gps_filtering_enabled"
        label={p(@locale, "gps_noise_filtering")}
        checked={@saved["gps_filtering_enabled"] != false}
      />
      <.toggle
        name="live_map_enabled"
        label={p(@locale, "live_mode")}
        checked={@saved["live_map_enabled"] != false}
      />
      <p class="text-sm [overflow-wrap:anywhere]">{p(@locale, "show_new_points_in_real_time")}</p>
      <button type="submit" class="btn btn-sm btn-primary btn-block">{p(@locale, "apply_settings")}</button>
    </form>
    <div class="flex flex-col gap-2">
      <button
        id="native-recalculate"
        type="button"
        class="btn btn-sm btn-outline"
        phx-click="settings:recalculate"
        data-confirm={j(@locale, "settings.confirm_recalculate_user_data")}
      >
        {p(@locale, "recalculate_tracks_stats")}
      </button>
      <button
        id="native-reapply-anomalies"
        type="button"
        class="btn btn-sm btn-outline"
        phx-click="settings:reapply_anomalies"
        data-confirm={j(@locale, "settings.confirm_reapply_anomaly_filter")}
      >
        {p(@locale, "re_evaluate_past_data")}
      </button>
      <button
        id="native-settings-reset"
        type="button"
        class="btn btn-sm btn-outline"
        phx-click="settings:reset"
        data-confirm={j(@locale, "settings.confirm_reset")}
      >
        {p(@locale, "reset_to_defaults_2")}
      </button>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :min, :string, required: true
  attr :max, :string, default: nil
  attr :step, :string, required: true
  attr :type, :string, default: "number"

  defp number(assigns) do
    ~H"""
    <label class="form-control w-full min-w-0">
      <span class="label-text text-sm font-medium">{@label}</span>
      <input
        type={@type}
        name={@name}
        value={@value}
        min={@min}
        max={@max}
        step={@step}
        class={
          if @type == "range",
            do: "range range-sm w-full",
            else: "input input-sm input-bordered w-full"
        }
      />
    </label>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, default: false

  defp toggle(assigns) do
    ~H"""
    <label class="label cursor-pointer justify-start gap-3">
      <input type="hidden" name={@name} value="false" />
      <input type="checkbox" name={@name} value="true" class="toggle toggle-sm" checked={@checked} />
      <span class="label-text text-sm min-w-0">{@label}</span>
    </label>
    """
  end

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
  defp j(locale, key), do: t(locale, "javascript." <> key, %{})
end
