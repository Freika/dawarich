defmodule DawarichWeb.NativeMapSettingsTransport do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :settings, :map, default: nil
  attr :saved, :map, required: true
  attr :dirty, :list, default: nil
  attr :csrf_token, :string, default: nil

  def section(assigns) do
    saved = assigns.saved["enabled_transportation_modes"] || []
    chosen = (assigns.settings && assigns.settings.draft_modes) || saved

    assigns =
      assign(assigns,
        modes: Dawarich.Settings.Api.modes(),
        chosen: chosen,
        transport_dirty: Enum.sort(chosen) != Enum.sort(saved)
      )

    ~H"""
    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-dirty-scope="transportation"
      phx-mounted={keep_open()}
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="car" class="h-4 w-4 opacity-70 shrink-0" />
          {p(@locale, "transportation_mode_detection")}
          <DawarichWeb.NativeMapSettingsFields.dirty_badge fields={@dirty} locale={@locale} />
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

  defp keep_open, do: Phoenix.LiveView.JS.ignore_attributes(["open"])
  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
