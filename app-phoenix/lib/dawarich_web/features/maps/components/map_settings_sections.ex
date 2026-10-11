defmodule DawarichWeb.MapSettingsSections do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [pro_badge: 1]

  alias Dawarich.MapPage
  alias DawarichWeb.Icon

  @tile_categories [
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

  @poi_groups [
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

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def map_sections(assigns) do
    assigns = assign(assigns, tile_categories: @tile_categories, poi_groups: @poi_groups)

    ~H"""
    <details class="collapse collapse-arrow bg-base-200 rounded-lg">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="layer" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "base_map_layers")}
          <.pro_badge
            restricted={!@page.full_access}
            url={@page.badge_url}
            locale={@locale}
            preview={false}
          />
        </span>
      </summary>
      <div class="collapse-content space-y-1">
        <p :if={@page.full_access} class="text-xs text-base-content/60 mb-2">
          {s(@locale, "toggle_base_map_elements_changes_apply_immediately")}
        </p>
        <p :if={!@page.full_access} class="text-xs text-warning mb-2">
          {s(@locale, "pro_feature_you_can_preview_changes_here_but_they_won")}
        </p>
        <div :for={{key, label, description, custom} <- @tile_categories} class="form-control">
          <label class="label cursor-pointer justify-start gap-3 py-1">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              data-tile-category={key}
              data-custom-supported={to_string(custom)}
              data-action="change->maps--maplibre#toggleTileCategory"
              checked={!MapPage.member?(@page.hidden_tile_categories, key)}
            />
            <div>
              <span class="label-text text-sm font-medium">{s(@locale, label)}</span>
              <p class="text-xs text-base-content/60">{s(@locale, description)}</p>
            </div>
          </label>
        </div>
        <p class="text-xs text-base-content/60 mt-2">
          {s(@locale, "the_custom_style_draws_no_labels_or_points_of_interest")}
        </p>
      </div>
    </details>

    <details class="collapse collapse-arrow bg-base-200 rounded-lg">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="map-pin" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "points_of_interest")}
          <.pro_badge
            restricted={!@page.full_access}
            url={@page.badge_url}
            locale={@locale}
            preview={false}
          />
        </span>
      </summary>
      <div class="collapse-content space-y-1">
        <p :if={@page.full_access} class="text-xs text-base-content/60 mb-2">
          {s(@locale, "choose_which_poi_categories_appear_on_the_map")}
        </p>
        <p :if={!@page.full_access} class="text-xs text-warning mb-2">
          {s(@locale, "pro_feature_you_can_preview_changes_here_but_they_won")}
        </p>
        <div :for={{key, label, description} <- @poi_groups} class="form-control">
          <label class="label cursor-pointer justify-start gap-3 py-1">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-accent"
              data-poi-group={key}
              data-action="change->maps--maplibre#togglePoiGroup"
              checked={!MapPage.member?(@page.disabled_poi_groups, key)}
            />
            <div>
              <span class="label-text text-sm font-medium">{s(@locale, label)}</span>
              <p class="text-xs text-base-content/60">{s(@locale, description)}</p>
            </div>
          </label>
        </div>
      </div>
    </details>

    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-map-settings-dirty-target="section"
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="route" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "track_generation")}
          <span
            class="badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center hidden"
            data-dirty-badge
          ></span>
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <div class="form-control w-full">
          <label class="label" for="meters-between-routes">
            <span class="label-text font-medium">{s(@locale, "track_split_distance")}</span>
          </label>
          <label class="input input-bordered flex items-center gap-2">
            <input
              type="number"
              id="meters-between-routes"
              name="metersBetweenRoutes"
              min="1"
              step="1"
              value="500"
              required
              class="grow"
            />
            <span class="text-base-content/60">{s(@locale, "track_split_distance_unit")}</span>
          </label>
          <p class="text-xs text-base-content/60 mt-1">{s(@locale, "track_split_distance_hint")}</p>
        </div>

        <div class="form-control w-full">
          <label class="label" for="minutes-between-routes">
            <span class="label-text font-medium">{s(@locale, "track_split_time")}</span>
          </label>
          <label class="input input-bordered flex items-center gap-2">
            <input
              type="number"
              id="minutes-between-routes"
              name="minutesBetweenRoutes"
              min="1"
              max="1440"
              step="1"
              value="30"
              required
              class="grow"
            />
            <span class="text-base-content/60">{s(@locale, "track_split_time_unit")}</span>
          </label>
          <p class="text-xs text-base-content/60 mt-1">{s(@locale, "track_split_time_hint")}</p>
        </div>

        <button
          type="button"
          class="btn btn-sm btn-outline btn-block"
          data-action="click->maps--maplibre#recalculateUserData"
        >
          <Icon.icon name="refresh-ccw" class="size-6" />
          {s(@locale, "recalculate_tracks_stats")}
        </button>
        <p class="text-xs text-base-content/60">
          {s(@locale, "rebuild_tracks_stats_and_digests_from_your_current_points_without")}
        </p>
      </div>
    </details>

    <details
      class="collapse collapse-arrow bg-base-200 rounded-lg"
      data-map-settings-dirty-target="section"
    >
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="cloud-fog" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "fog_of_war")}
          <span
            class="badge badge-outline badge-warning badge-sm tooltip tooltip-left ml-auto mr-1 self-center hidden"
            data-dirty-badge
          ></span>
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-medium">{s(@locale, "fog_of_war_radius")}</span>
            <span class="label-text-alt" data-maps--maplibre-target="fogRadiusValue">{t(
              @locale,
              "units.meters_compact",
              %{value: 1000}
            )}</span>
          </label>
          <input
            type="range"
            name="fogOfWarRadius"
            min="5"
            max="2000"
            step="5"
            value="1000"
            class="range range-sm"
            data-action="input->maps--maplibre#updateFogRadiusDisplay"
          />
          <div class="w-full flex justify-between text-xs px-2 mt-1">
            <span>{t(@locale, "units.meters_compact", %{value: 5})}</span>
            <span>{t(@locale, "units.meters_compact", %{value: 1000})}</span>
            <span>{t(@locale, "units.meters_compact", %{value: 2000})}</span>
          </div>
          <p class="text-xs text-base-content/60 mt-1">
            {s(@locale, "clear_radius_around_visited_points")}
          </p>
        </div>

        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-medium">{s(@locale, "fog_of_war_threshold")}</span>
            <span class="label-text-alt" data-maps--maplibre-target="fogThresholdValue">1</span>
          </label>
          <input
            type="range"
            name="fogOfWarThreshold"
            min="1"
            max="10"
            step="1"
            value="1"
            class="range range-sm"
            data-action="input->maps--maplibre#updateFogThresholdDisplay"
          />
          <div class="w-full flex justify-between text-xs px-2 mt-1">
            <span>1</span>
            <span>5</span>
            <span>10</span>
          </div>
          <p class="text-xs text-base-content/60 mt-1">{s(@locale, "minimum_points_to_clear_fog")}</p>
        </div>
      </div>
    </details>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
