defmodule DawarichWeb.NativeMapSettingsTab do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Assets, Icon}

  @styles ~w(light dark white black grayscale custom)
  @tokens [
    {"bg", "background"},
    {"water", "water"},
    {"parks", "parks"},
    {"buildings", "buildings"},
    {"railway", "railways"},
    {"boundaries", "boundaries"},
    {"road_motorway", "motorway_roads"},
    {"road_primary", "primary_roads"},
    {"road_residential", "residential_roads"},
    {"road_default", "other_roads"}
  ]
  @tiles [
    {"roads", "roads", "streets_highways_and_paths", true},
    {"road_labels", "road_labels", "street_names_and_route_shields", false},
    {"rail", "railways", "train_tracks_and_rail_lines", true},
    {"buildings", "buildings", "building_footprints", true},
    {"address_labels", "address_labels", "building_numbers_visible_at_high_zoom", false},
    {"pois", "points_of_interest", "master_toggle_for_all_poi_groups_below", false},
    {"place_labels", "place_names", "cities_neighborhoods_regions_and_countries", false},
    {"water_labels", "water_labels", "ocean_lake_and_river_names", false},
    {"water", "water", "oceans_lakes_rivers_and_streams", true},
    {"landuse", "land_use", "parks_schools_hospitals_airports_etc", true},
    {"boundaries", "boundaries", "country_and_administrative_borders", true}
  ]
  @poi [
    {"food_drink", "food_drink", "restaurants_cafes_bars_bakeries_fast_food"},
    {"shopping", "shopping", "supermarkets_clothes_electronics_books_beauty"},
    {"transport", "transport", "stations_bus_stops_airports_fuel_parking"},
    {"cycling", "cycling", "bike_parking_rental_and_repair_stations"},
    {"nature_leisure", "nature_leisure", "parks_forests_beaches_playgrounds_stadiums"},
    {"tourism", "tourism_culture", "museums_theatres_attractions_viewpoints_hotels"},
    {"services", "services_civic", "post_offices_libraries_schools_hospitals_police_banks"},
    {"urban_amenities", "urban_amenities",
     "benches_toilets_drinking_water_fountains_recycling_shelters"}
  ]

  attr :locale, :string, required: true
  attr :panel, :string, required: true
  attr :settings, :map, default: nil
  attr :page, :map, required: true
  attr :csrf_token, :string, default: nil

  def tab(assigns) do
    settings = assigns.settings
    saved = (settings && settings.saved) || Dawarich.Settings.MapForm.defaults()
    maps = saved["maps"] || %{}
    theme = saved["maps_maplibre_custom_theme"] || %{}
    custom = saved["maps_maplibre_style"] == "custom"

    assigns =
      assign(assigns,
        saved: saved,
        restricted: !!(settings && settings.restricted),
        themes: (settings && settings.themes) || [],
        custom: custom,
        preset:
          custom && Enum.find((settings && settings.themes) || [], &(&1.key == theme["base"])),
        theme_tokens: theme["tokens"] || %{},
        hidden_tiles: maps["hidden_tile_categories"] || [],
        disabled_poi: maps["disabled_poi_groups"] || [],
        styles: @styles,
        tokens: @tokens,
        tiles: @tiles,
        poi: @poi
      )

    ~H"""
    <div class={["tab-content", @panel == "settings" && "active"]} data-tab-content="settings">
      <DawarichWeb.NativeMapSettingsStatus.status settings={@settings} locale={@locale} />
      <form
        id="native-map-settings-form"
        class="space-y-4"
        phx-change="settings:form"
        phx-submit="settings:apply"
      >
        <details open class="collapse collapse-arrow bg-base-200 rounded-lg" phx-mounted={keep_open()}>
          <summary class="collapse-title font-medium min-h-0 cursor-pointer">
            <span class="flex items-center gap-2">
              <Icon.icon name="palette" class="h-4 w-4 opacity-70 shrink-0" />
              {p(@locale, "appearance")}
            </span>
          </summary>
          <div class="collapse-content space-y-4">
            <p :if={@restricted} class="text-xs text-warning">
              {p(
                @locale,
                "custom_map_colors_layer_colors_and_vector_tiles_are_pro"
              )}
            </p>
            <div>
              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-medium">{p(@locale, "map_style")}</span>
                </label>
                <select
                  class="select select-bordered w-full"
                  name="mapStyle"
                  aria-label={p(@locale, "map_style")}
                >
                  <option
                    :for={style <- @styles}
                    value={style}
                    selected={(@saved["maps_maplibre_style"] || "light") == style}
                  >
                    {p(@locale, style)}
                  </option>
                </select>
              </div>

              <div class="mt-3 space-y-3">
                <div>
                  <span class="label-text text-sm">{p(@locale, "color_themes")}</span>
                  <div class="grid grid-cols-6 gap-1.5 mt-1">
                    <button
                      :for={theme <- @themes}
                      type="button"
                      class="w-full overflow-hidden rounded-md border border-base-300 ring-primary ring-offset-base-100 transition hover:scale-105 focus:outline-none focus-visible:ring-2"
                      style={"height: 32px; background-image: url('#{Assets.stylesheet_path("poster_themes/#{theme.key}.webp")}'); background-size: cover; background-position: center;"}
                      title={theme.name}
                      aria-label={
                        t(@locale, "map.maplibre.settings_panel.theme_aria_label", %{
                          "theme" => theme.name
                        })
                      }
                      data-key={theme.key}
                      data-name={theme.name}
                      phx-click="settings:theme_preset"
                      phx-value-key={theme.key}
                    ></button>
                  </div>
                  <p class="text-xs opacity-70 mt-1">{if @preset, do: @preset.name}</p>
                </div>

                <details
                  class={[!@custom && "hidden", "collapse collapse-arrow bg-base-100 rounded-lg"]}
                  phx-mounted={keep_open()}
                >
                  <summary class="collapse-title text-sm min-h-0 cursor-pointer select-none">
                    {p(
                      @locale,
                      "customize_colors"
                    )}
                  </summary>
                  <div class="collapse-content space-y-1">
                    <label :for={{token, label} <- @tokens} class="flex items-center gap-2">
                      <input
                        type="color"
                        class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
                        data-token={token}
                        name={"tokens[#{token}]"}
                        value={@theme_tokens[token]}
                        phx-debounce="300"
                      />
                      <span class="label-text text-sm flex-1">{p(@locale, label)}</span>
                      <span class="text-xs opacity-60 tabular-nums" data-token={token}>{@theme_tokens[
                        token
                      ]}</span>
                    </label>
                  </div>
                </details>
              </div>
            </div>

            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-3">
                <input
                  type="checkbox"
                  name="globeProjection"
                  class="toggle toggle-primary"
                  checked={@saved["globe_projection"] == true}
                />
                <span class="label-text font-medium">{p(@locale, "globe_view")}</span>
                <DawarichWeb.MapParts.pro_badge
                  restricted={@restricted}
                  url={@page[:badge_url] || ""}
                  locale={@locale}
                  preview={false}
                />
              </label>
              <p class="text-sm text-base-content/60 mt-1">
                {p(
                  @locale,
                  "render_map_as_a_3d_globe_requires_page_reload"
                )}
              </p>
            </div>

            <div class="divider"></div>

            <div class="form-control w-full space-y-1">
              <label class="label">
                <span class="label-text font-medium">{p(@locale, "layer_colors")}</span>
              </label>
              <label class="flex items-center gap-2">
                <input
                  type="color"
                  name="trackColor"
                  class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
                  value={@saved["track_color"]}
                  phx-debounce="300"
                />
                <span class="label-text text-sm flex-1">{p(@locale, "tracks")}</span>
                <span class="text-xs opacity-60 tabular-nums" data-layer-color-value="trackColor">{@saved[
                  "track_color"
                ]}</span>
              </label>
              <button
                type="button"
                class="btn btn-xs btn-ghost self-start"
                phx-click="settings:track_color_reset"
              >
                <Icon.icon name="rotate-ccw" class="h-3 w-3" />
                {p(@locale, "reset_to_defaults")}
              </button>
            </div>

            <div class="divider"></div>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">{p(@locale, "distance_unit")}</span>
              </label>
              <div class="flex gap-4">
                <label
                  :for={{unit, key} <- [{"km", "kilometers"}, {"mi", "miles"}]}
                  class="label cursor-pointer gap-2 py-0"
                >
                  <input
                    type="radio"
                    name="distanceUnit"
                    value={unit}
                    class="radio radio-sm radio-primary"
                    checked={((@saved["maps"] || %{})["distance_unit"] || "km") == unit}
                  />
                  <span class="label-text text-sm">{p(@locale, key)}</span>
                </label>
              </div>
            </div>

            <div class="divider"></div>

            <div class="form-control w-full">
              <label class="label">
                <span class="label-text font-medium">{p(@locale, "custom_basemap_url")}</span>
              </label>
              <input
                type="url"
                name="vectorTilesUrl"
                aria-label={p(@locale, "custom_basemap_url")}
                placeholder="https://tiles.example.com/{z}/{x}/{y}.mvt"
                class="input input-bordered input-sm w-full"
                value={@saved["maps_maplibre_tiles_url"]}
                phx-debounce="blur"
              />
              <p class="text-xs text-base-content/60 mt-1">
                {p(
                  @locale,
                  "serve_the_base_map_from_your_own_source_accepts_protomaps"
                )}
              </p>

              <label class="label cursor-pointer justify-start gap-2 mt-2 py-0">
                <input
                  type="checkbox"
                  name="tilesFallback"
                  class="checkbox checkbox-sm checkbox-primary"
                  checked={@saved["maps_maplibre_tiles_fallback"] == true}
                />
                <span class="label-text text-sm">{p(@locale, "fill_gaps_with_the_default_basemap")}</span>
              </label>
              <p class="text-xs text-base-content/60 mt-1">
                {p(
                  @locale,
                  "uncovered_areas_are_drawn_from_dawarich_s_default_tile_server"
                )}
              </p>
            </div>
          </div>
        </details>

        <.toggle_section
          icon="layer"
          title={p(@locale, "base_map_layers")}
          intro={
            if @page.full_access,
              do: p(@locale, "toggle_base_map_elements_changes_apply_immediately"),
              else: p(@locale, "pro_feature_you_can_preview_changes_here_but_they_won")
          }
          intro_class={
            if @page.full_access,
              do: "text-xs text-base-content/60 mb-2",
              else: "text-xs text-warning mb-2"
          }
          restricted={@restricted}
          page={@page}
          locale={@locale}
        >
          <div :for={{key, label, description, custom} <- @tiles} class="form-control">
            <label class="label cursor-pointer justify-start gap-3 py-1">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                data-tile-category={key}
                data-custom-supported={to_string(custom)}
                checked={key not in @hidden_tiles}
                phx-click="settings:tile_category"
                phx-value-category={key}
                phx-value-enabled={to_string(key in @hidden_tiles)}
              />
              <div>
                <span class="label-text text-sm font-medium">{p(@locale, label)}</span>
                <p class="text-xs text-base-content/60">{p(@locale, description)}</p>
              </div>
            </label>
          </div>
          <:footer>
            <p class="text-xs text-base-content/60 mt-2">
              {p(
                @locale,
                "the_custom_style_draws_no_labels_or_points_of_interest"
              )}
            </p>
          </:footer>
        </.toggle_section>

        <.toggle_section
          icon="map-pin"
          title={p(@locale, "points_of_interest")}
          intro={
            if @page.full_access,
              do: p(@locale, "choose_which_poi_categories_appear_on_the_map"),
              else: p(@locale, "pro_feature_you_can_preview_changes_here_but_they_won")
          }
          intro_class={
            if @page.full_access,
              do: "text-xs text-base-content/60 mb-2",
              else: "text-xs text-warning mb-2"
          }
          restricted={@restricted}
          page={@page}
          locale={@locale}
        >
          <div :for={{key, label, description} <- @poi} class="form-control">
            <label class="label cursor-pointer justify-start gap-3 py-1">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-accent"
                data-poi-group={key}
                checked={key not in @disabled_poi}
                phx-click="settings:poi_group"
                phx-value-group={key}
                phx-value-enabled={to_string(key in @disabled_poi)}
              />
              <div>
                <span class="label-text text-sm font-medium">{p(@locale, label)}</span>
                <p class="text-xs text-base-content/60">{p(@locale, description)}</p>
              </div>
            </label>
          </div>
        </.toggle_section>

        <DawarichWeb.NativeMapSettingsTabMore.sections
          locale={@locale}
          settings={@settings}
          saved={@saved}
          csrf_token={@csrf_token}
        />
      </form>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :intro, :string, required: true
  attr :intro_class, :string, required: true
  attr :restricted, :boolean, required: true
  attr :page, :map, required: true
  attr :locale, :string, required: true
  slot :inner_block, required: true
  slot :footer

  defp toggle_section(assigns) do
    ~H"""
    <details class="collapse collapse-arrow bg-base-200 rounded-lg" phx-mounted={keep_open()}>
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name={@icon} class="h-4 w-4 opacity-70 shrink-0" />
          {@title}
          <DawarichWeb.MapParts.pro_badge
            restricted={@restricted}
            url={@page[:badge_url] || ""}
            locale={@locale}
            preview={false}
          />
        </span>
      </summary>
      <div class="collapse-content space-y-1">
        <p class={@intro_class}>{@intro}</p>
        {render_slot(@inner_block)}
        {render_slot(@footer)}
      </div>
    </details>
    """
  end

  defp keep_open, do: Phoenix.LiveView.JS.ignore_attributes(["open"])
  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
