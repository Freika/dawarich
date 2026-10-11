defmodule DawarichWeb.NativeMapSettingsSections do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Settings.MapForm
  alias Phoenix.LiveView.JS

  @token_labels %{
    "bg" => "background",
    "water" => "water",
    "parks" => "parks",
    "buildings" => "buildings",
    "railway" => "railways",
    "boundaries" => "boundaries",
    "road_motorway" => "motorway_roads",
    "road_primary" => "primary_roads",
    "road_residential" => "residential_roads",
    "road_default" => "other_roads"
  }

  @tiles [
    {"roads", "roads", "streets_highways_and_paths"},
    {"road_labels", "road_labels", "street_names_and_route_shields"},
    {"rail", "railways", "train_tracks_and_rail_lines"},
    {"buildings", "buildings", "building_footprints"},
    {"address_labels", "address_labels", "building_numbers_visible_at_high_zoom"},
    {"pois", "points_of_interest", "master_toggle_for_all_poi_groups_below"},
    {"place_labels", "place_names", "cities_neighborhoods_regions_and_countries"},
    {"water_labels", "water_labels", "ocean_lake_and_river_names"},
    {"water", "water", "oceans_lakes_rivers_and_streams"},
    {"landuse", "land_use", "parks_schools_hospitals_airports_etc"},
    {"boundaries", "boundaries", "country_and_administrative_borders"}
  ]

  @poi [
    {"food_drink", "food_drink"},
    {"shopping", "shopping"},
    {"transport", "transport"},
    {"cycling", "cycling"},
    {"nature_leisure", "nature_leisure"},
    {"tourism", "tourism_culture"},
    {"services", "services_civic"},
    {"urban_amenities", "urban_amenities"}
  ]

  attr :settings, :map, required: true
  attr :locale, :string, required: true

  def sections(assigns) do
    saved = assigns.settings.saved
    maps = saved["maps"] || %{}
    theme = saved["maps_maplibre_custom_theme"] || %{}

    assigns =
      assign(assigns,
        saved: saved,
        hidden: List.wrap(maps["hidden_tile_categories"]),
        disabled: List.wrap(maps["disabled_poi_groups"]),
        unit: saved["distance_unit"] || "km",
        base: theme["base"],
        tokens: theme["tokens"] || %{},
        token_keys: MapForm.tokens(),
        token_labels: @token_labels,
        tiles: @tiles,
        poi: @poi
      )

    ~H"""
    <div id="native-map-settings-sections" class="space-y-4 min-w-0">
      <p :if={@settings.restricted} class="text-xs text-warning">
        {p(@locale, "custom_map_colors_layer_colors_and_vector_tiles_are_pro")}
      </p>
      <section id="native-theme-presets" class="min-w-0">
        <h3 class="font-semibold text-sm">{p(@locale, "color_themes")}</h3>
        <div class="flex flex-wrap gap-1.5 mt-1">
          <button
            :for={theme <- @settings.themes}
            type="button"
            class={["btn btn-xs", if(theme.key == @base, do: "btn-primary", else: "btn-outline")]}
            data-theme-key={theme.key}
            aria-pressed={to_string(theme.key == @base)}
            aria-label={p(@locale, "theme_aria_label", %{theme: theme.name})}
            phx-click={JS.push("settings:theme_preset", value: %{key: theme.key})}
          >
            <span class="[overflow-wrap:anywhere]">{theme.name}</span>
          </button>
        </div>
      </section>
      <form
        :if={@saved["maps_maplibre_style"] == "custom"}
        id="native-theme-form"
        phx-submit="settings:theme"
        class="space-y-1"
      >
        <h3 class="font-semibold text-sm">{p(@locale, "customize_colors")}</h3>
        <label :for={token <- @token_keys} class="flex items-center gap-2 min-w-0">
          <input
            type="color"
            name={"tokens[#{token}]"}
            value={@tokens[token] || "#000000"}
            class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
          />
          <span class="label-text text-sm flex-1 min-w-0">{p(@locale, @token_labels[token])}</span>
        </label>
        <button type="submit" class="btn btn-sm btn-primary">{p(@locale, "apply_settings")}</button>
      </form>
      <form id="native-display-form" phx-submit="settings:appearance" class="space-y-2">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="hidden" name="globe_projection" value="false" />
          <input
            type="checkbox"
            name="globe_projection"
            value="true"
            class="toggle toggle-sm"
            checked={@saved["globe_projection"] == true}
          />
          <span class="label-text text-sm min-w-0">{p(@locale, "globe_view")}</span>
        </label>
        <p class="text-xs text-base-content/60">
          {p(@locale, "render_map_as_a_3d_globe_requires_page_reload")}
        </p>
        <label class="flex items-center gap-2">
          <input
            type="color"
            name="track_color"
            value={@saved["track_color"]}
            class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
          />
          <span class="label-text text-sm flex-1">{p(@locale, "tracks")}</span>
        </label>
        <fieldset class="flex flex-wrap gap-4">
          <legend class="label-text text-sm">{p(@locale, "distance_unit")}</legend>
          <label
            :for={{unit, label} <- [{"km", "kilometers"}, {"mi", "miles"}]}
            class="label cursor-pointer gap-2 py-0"
          >
            <input
              type="radio"
              name="distance_unit"
              value={unit}
              class="radio radio-sm"
              checked={@unit == unit}
            />
            <span class="label-text text-sm">{p(@locale, label)}</span>
          </label>
        </fieldset>
        <div class="flex flex-wrap gap-2">
          <button type="submit" class="btn btn-sm btn-primary">{p(@locale, "apply_settings")}</button>
          <button
            id="native-track-color-reset"
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="settings:track_color_reset"
          >
            {p(@locale, "reset_to_defaults")}
          </button>
        </div>
      </form>
      <form id="native-layers-form" phx-submit="settings:layers" class="space-y-1">
        <h3 class="font-semibold text-sm">{p(@locale, "base_map_layers")}</h3>
        <label
          :for={{key, label, hint} <- @tiles}
          class="label cursor-pointer justify-start gap-3 py-1"
        >
          <input
            type="checkbox"
            name="tiles[]"
            value={key}
            class="toggle toggle-sm"
            checked={key not in @hidden}
          />
          <span class="min-w-0">
            <span class="label-text text-sm font-medium">{p(@locale, label)}</span>
            <span class="block text-xs text-base-content/60">{p(@locale, hint)}</span>
          </span>
        </label>
        <h3 class="font-semibold text-sm pt-2">{p(@locale, "points_of_interest")}</h3>
        <label :for={{key, label} <- @poi} class="label cursor-pointer justify-start gap-3 py-1">
          <input
            type="checkbox"
            name="poi[]"
            value={key}
            class="toggle toggle-sm toggle-accent"
            checked={key not in @disabled}
          />
          <span class="label-text text-sm min-w-0">{p(@locale, label)}</span>
        </label>
        <button type="submit" class="btn btn-sm btn-primary">{p(@locale, "apply_settings")}</button>
      </form>
      <DawarichWeb.NativeMapSettingsAdvanced.advanced saved={@saved} locale={@locale} />
    </div>
    """
  end

  defp p(locale, key, bindings \\ %{}),
    do: t(locale, "map.maplibre.settings_panel." <> key, bindings)
end
