defmodule DawarichWeb.NativeMapSettingsBasemap do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

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
  attr :restricted, :boolean, required: true
  attr :page, :map, required: true
  attr :hidden_tiles, :list, required: true
  attr :disabled_poi, :list, required: true

  def sections(assigns) do
    assigns = assign(assigns, tiles: @tiles, poi: @poi)

    ~H"""
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
          />
          <div>
            <span class="label-text text-sm font-medium">{p(@locale, label)}</span>
            <p class="text-xs text-base-content/60">{p(@locale, description)}</p>
          </div>
        </label>
      </div>
    </.toggle_section>
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
