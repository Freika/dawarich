defmodule DawarichWeb.MapSettingsAppearance do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapParts, only: [pro_badge: 1]

  alias DawarichWeb.{Assets, Icon}

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

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def appearance(assigns) do
    assigns = assign(assigns, :tokens, @tokens)

    ~H"""
    <details open class="collapse collapse-arrow bg-base-200 rounded-lg">
      <summary class="collapse-title font-medium min-h-0 cursor-pointer">
        <span class="flex items-center gap-2">
          <Icon.icon name="palette" class="h-4 w-4 opacity-70 shrink-0" />
          {s(@locale, "appearance")}
        </span>
      </summary>
      <div class="collapse-content space-y-4">
        <p :if={!@page.full_access} class="text-xs text-warning">
          {s(@locale, "custom_map_colors_layer_colors_and_vector_tiles_are_pro")}
        </p>
        <div data-controller="map-theme-editor">
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-medium">{s(@locale, "map_style")}</span>
            </label>
            <select
              class="select select-bordered w-full"
              name="mapStyle"
              data-map-theme-editor-target="styleSelect"
              data-action="change->maps--maplibre#updateMapStyle change->map-theme-editor#styleChanged"
            >
              <option value="light" selected>{s(@locale, "light")}</option>
              <option value="dark">{s(@locale, "dark")}</option>
              <option value="white">{s(@locale, "white")}</option>
              <option value="black">{s(@locale, "black")}</option>
              <option value="grayscale">{s(@locale, "grayscale")}</option>
              <option value="custom">{s(@locale, "custom")}</option>
            </select>
          </div>

          <div class="mt-3 space-y-3">
            <div>
              <span class="label-text text-sm">{s(@locale, "color_themes")}</span>
              <div class="grid grid-cols-6 gap-1.5 mt-1">
                <button
                  :for={theme <- @page.themes}
                  type="button"
                  class="w-full overflow-hidden rounded-md border border-base-300 ring-primary ring-offset-base-100 transition hover:scale-105 focus:outline-none focus-visible:ring-2"
                  style={"height: 32px; background-image: url('#{Assets.stylesheet_path("poster_themes/#{theme.key}.webp")}'); background-size: cover; background-position: center;"}
                  title={to_string(theme.name)}
                  aria-label={s(@locale, "theme_aria_label", %{theme: theme.name})}
                  data-map-theme-editor-target="swatch"
                  data-key={theme.key}
                  data-name={to_string(theme.name)}
                  data-action="click->map-theme-editor#pickPreset"
                ></button>
              </div>
              <p class="text-xs opacity-70 mt-1" data-map-theme-editor-target="presetLabel"></p>
            </div>

            <details
              class="hidden collapse collapse-arrow bg-base-100 rounded-lg"
              data-map-theme-editor-target="block"
            >
              <summary class="collapse-title text-sm min-h-0 cursor-pointer select-none">
                {s(@locale, "customize_colors")}
              </summary>
              <div class="collapse-content space-y-1">
                <label :for={{token, label} <- @tokens} class="flex items-center gap-2">
                  <input
                    type="color"
                    class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
                    data-map-theme-editor-target="token"
                    data-token={token}
                    data-action="input->map-theme-editor#tokenChanged"
                  />
                  <span class="label-text text-sm flex-1">{s(@locale, label)}</span>
                  <span
                    class="text-xs opacity-60 tabular-nums"
                    data-map-theme-editor-target="tokenValue"
                    data-token={token}
                  ></span>
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
              data-maps--maplibre-target="globeToggle"
              data-action="change->maps--maplibre#toggleGlobe"
            />
            <span class="label-text font-medium">{s(@locale, "globe_view")}</span>
            <.pro_badge
              restricted={!@page.full_access}
              url={@page.badge_url}
              locale={@locale}
              preview={false}
            />
          </label>
          <p class="text-sm text-base-content/60 mt-1">
            {s(@locale, "render_map_as_a_3d_globe_requires_page_reload")}
          </p>
        </div>

        <div class="divider"></div>

        <div class="form-control w-full space-y-1">
          <label class="label">
            <span class="label-text font-medium">{s(@locale, "layer_colors")}</span>
          </label>
          <label class="flex items-center gap-2">
            <input
              type="color"
              name="trackColor"
              class="h-7 w-9 cursor-pointer rounded border border-base-300 bg-base-100 p-0.5"
              data-action="input->maps--maplibre#updateTrackColor"
            />
            <span class="label-text text-sm flex-1">{s(@locale, "tracks")}</span>
            <span class="text-xs opacity-60 tabular-nums" data-layer-color-value="trackColor"></span>
          </label>
          <button
            type="button"
            class="btn btn-xs btn-ghost self-start"
            data-action="click->maps--maplibre#resetLayerColors"
          >
            <Icon.icon name="rotate-ccw" class="h-3 w-3" />
            {s(@locale, "reset_to_defaults")}
          </button>
        </div>

        <div class="divider"></div>

        <div class="form-control">
          <label class="label">
            <span class="label-text font-medium">{s(@locale, "distance_unit")}</span>
          </label>
          <div class="flex gap-4">
            <label class="label cursor-pointer gap-2 py-0">
              <input
                type="radio"
                name="distanceUnit"
                value="km"
                class="radio radio-sm radio-primary"
                data-action="change->maps--maplibre#updateDistanceUnit"
              />
              <span class="label-text text-sm">{s(@locale, "kilometers")}</span>
            </label>
            <label class="label cursor-pointer gap-2 py-0">
              <input
                type="radio"
                name="distanceUnit"
                value="mi"
                class="radio radio-sm radio-primary"
                data-action="change->maps--maplibre#updateDistanceUnit"
              />
              <span class="label-text text-sm">{s(@locale, "miles")}</span>
            </label>
          </div>
        </div>

        <div class="divider"></div>

        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-medium">{s(@locale, "custom_basemap_url")}</span>
          </label>
          <input
            type="url"
            name="vectorTilesUrl"
            placeholder="https://tiles.example.com/{z}/{x}/{y}.mvt"
            class="input input-bordered input-sm w-full"
            data-action="change->maps--maplibre#updateVectorTilesUrl"
          />
          <p class="text-xs text-base-content/60 mt-1">
            {s(@locale, "serve_the_base_map_from_your_own_source_accepts_protomaps")}
          </p>

          <label class="label cursor-pointer justify-start gap-2 mt-2 py-0">
            <input
              type="checkbox"
              name="tilesFallback"
              class="checkbox checkbox-sm checkbox-primary"
              data-action="change->maps--maplibre#updateTilesFallback"
            />
            <span class="label-text text-sm">{s(@locale, "fill_gaps_with_the_default_basemap")}</span>
          </label>
          <p class="text-xs text-base-content/60 mt-1">
            {s(@locale, "uncovered_areas_are_drawn_from_dawarich_s_default_tile_server")}
          </p>
        </div>
      </div>
    </details>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
  defp s(locale, key, bindings), do: t(locale, "map.maplibre.settings_panel." <> key, bindings)
end
