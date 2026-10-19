defmodule DawarichWeb.NativeMapSettingsTabMore do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :settings, :map, default: nil
  attr :saved, :map, required: true
  attr :csrf_token, :string, default: nil

  def sections(assigns) do
    dirty = (assigns.settings && assigns.settings[:dirty]) || %{}
    draft = (assigns.settings && assigns.settings[:draft]) || %{}
    saved = assigns.saved
    value = fn name, key -> if draft == %{}, do: saved[key], else: draft[name] end

    assigns =
      assign(assigns,
        dirty: dirty,
        meters: value.("metersBetweenRoutes", "meters_between_routes") || "500",
        minutes: value.("minutesBetweenRoutes", "minutes_between_routes") || "30",
        gps:
          if(draft == %{},
            do: saved["gps_filtering_enabled"] != false,
            else: draft["gpsFilteringEnabled"] == "on"
          ),
        radius: value.("fogOfWarRadius", "fog_of_war_meters") |> int(1000) |> clamp(5, 2000),
        threshold: value.("fogOfWarThreshold", "fog_of_war_threshold") |> int(1) |> clamp(1, 10),
        city:
          value.("minMinutesSpentInCity", "min_minutes_spent_in_city") |> int(60) |> clamp(5, 120)
      )

    ~H"""
    <.section
      icon="route"
      title={p(@locale, "track_generation")}
      dirty={@dirty["track"]}
      locale={@locale}
    >
      <DawarichWeb.NativeMapSettingsFields.number
        id="meters-between-routes"
        name="metersBetweenRoutes"
        label={p(@locale, "track_split_distance")}
        unit={p(@locale, "track_split_distance_unit")}
        hint={p(@locale, "track_split_distance_hint")}
        value={@meters}
      />
      <DawarichWeb.NativeMapSettingsFields.number
        id="minutes-between-routes"
        name="minutesBetweenRoutes"
        max="1440"
        label={p(@locale, "track_split_time")}
        unit={p(@locale, "track_split_time_unit")}
        hint={p(@locale, "track_split_time_hint")}
        value={@minutes}
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
      <DawarichWeb.NativeMapSettingsFields.range
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
      <DawarichWeb.NativeMapSettingsFields.range
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
            checked={@gps}
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
      <DawarichWeb.NativeMapSettingsFields.range
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

    <DawarichWeb.NativeMapSettingsTransport.section
      locale={@locale}
      settings={@settings}
      saved={@saved}
      dirty={@dirty["transportation"]}
      csrf_token={@csrf_token}
    />
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
          <DawarichWeb.NativeMapSettingsFields.dirty_badge fields={@dirty} locale={@locale} />
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        {render_slot(@inner_block)}
      </div>
    </details>
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

  defp meters(locale, value), do: t(locale, "units.meters_compact", %{"value" => value})
  defp keep_open, do: Phoenix.LiveView.JS.ignore_attributes(["open"])
  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
