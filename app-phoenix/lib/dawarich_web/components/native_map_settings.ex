defmodule DawarichWeb.NativeMapSettings do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  @styles ~w(light dark white black grayscale custom)

  attr :settings, :map, default: nil
  attr :locale, :string, required: true

  def panel(%{settings: nil} = assigns), do: ~H""

  def panel(assigns) do
    saved = assigns.settings.saved
    selected = assigns.settings.draft_modes || saved["enabled_transportation_modes"]

    assigns =
      assign(assigns,
        saved: saved,
        selected: selected,
        dirty: Enum.sort(selected) != Enum.sort(saved["enabled_transportation_modes"]),
        styles: @styles,
        modes: Dawarich.Settings.Api.modes()
      )

    ~H"""
    <section id="native-map-settings" class="space-y-4 min-w-0">
      <p :if={@settings.error} class="alert alert-error text-sm [overflow-wrap:anywhere]" role="alert">
        {error(@locale, @settings.error)}
      </p>
      <p
        :if={@settings[:notice]}
        id="native-settings-notice"
        class="alert alert-success text-sm"
        role="status"
      >
        {notice(@locale, @settings.notice)}
      </p>
      <form id="native-appearance-form" phx-submit="settings:appearance" class="space-y-2">
        <h3 class="font-semibold text-sm">{p(@locale, "appearance")}</h3>
        <label class="form-control">
          <span class="label-text text-xs">{p(@locale, "map_style")}</span>
          <select name="maps_maplibre_style" class="select select-sm select-bordered">
            <option
              :for={style <- @styles}
              value={style}
              selected={@saved["maps_maplibre_style"] == style}
            >
              {p(@locale, style)}
            </option>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text text-xs">{p(@locale, "custom_basemap_url")}</span>
          <input
            type="url"
            name="maps_maplibre_tiles_url"
            value={@saved["maps_maplibre_tiles_url"]}
            class="input input-sm input-bordered w-full [overflow-wrap:anywhere]"
          />
        </label>
        <label class="label cursor-pointer justify-start gap-2">
          <input type="hidden" name="maps_maplibre_tiles_fallback" value="false" />
          <input
            type="checkbox"
            name="maps_maplibre_tiles_fallback"
            value="true"
            class="toggle toggle-sm"
            checked={@saved["maps_maplibre_tiles_fallback"] == true}
          />
          <span class="label-text text-xs min-w-0">{p(@locale, "fill_gaps_with_the_default_basemap")}</span>
        </label>
        <button type="submit" class="btn btn-sm btn-primary">{p(@locale, "apply_settings")}</button>
      </form>
      <form
        id="native-transport-form"
        phx-change="settings:transport_change"
        phx-submit="settings:transport_apply"
        class="space-y-2"
      >
        <h3 class="font-semibold text-sm">{p(@locale, "transportation_mode_detection")}</h3>
        <div class="flex flex-wrap gap-2">
          <label :for={mode <- @modes} class="label cursor-pointer gap-1">
            <input
              type="checkbox"
              name="modes[]"
              value={mode}
              class="checkbox checkbox-xs"
              checked={mode in @selected}
            />
            <span class="label-text text-xs">{t(@locale, "transportation_modes.#{mode}", %{})}</span>
          </label>
        </div>
        <p class="text-xs text-base-content/60">
          {if @dirty,
            do: t(@locale, "javascript.settings.unsaved_transportation_changes", %{}),
            else: p(@locale, "make_changes_to_enable_the_apply_button")}
        </p>
        <button
          id="native-transport-apply"
          type="submit"
          class="btn btn-sm btn-primary"
          disabled={not @dirty}
          data-confirm={t(@locale, "javascript.settings.confirm_transportation_recalculation", %{})}
        >
          {p(@locale, "apply_settings")}
        </button>
      </form>
      <DawarichWeb.NativeMapSettingsSections.sections settings={@settings} locale={@locale} />
    </section>
    """
  end

  defp error(_locale, message) when is_binary(message), do: message

  defp error(locale, {:recalculation, :in_progress}),
    do:
      t(
        locale,
        "controllers.api.v1.recalculations.recalculation_already_in_progress_for_this_user",
        %{}
      )

  defp error(locale, {:anomalies, :in_progress}),
    do: t(locale, "controllers.api.v1.points.anomaly_re_evaluation_already_in_progress", %{})

  defp error(locale, {:recalculation, _}),
    do: t(locale, "javascript.messages.could_not_queue_recalculation_please_try_again", %{})

  defp error(locale, {:anomalies, _}),
    do: t(locale, "javascript.messages.could_not_queue_re_evaluation_please_try_again", %{})

  defp error(locale, _reason), do: t(locale, "javascript.messages.failed_to_update_settings", %{})

  defp notice(locale, {:live, enabled}),
    do: t(locale, "javascript.live_map." <> if(enabled, do: "enabled", else: "disabled"), %{})

  defp notice(locale, :recalculation),
    do: t(locale, "javascript.settings.recalculation_queued", %{})

  defp notice(locale, :anomalies), do: t(locale, "javascript.settings.re_evaluation_queued", %{})
  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
