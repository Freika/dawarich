defmodule DawarichWeb.NativeMapLayersTab do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  @tiles [
    {"Points", "pointsToggle", "dots-scattered", "points", "show_individual_location_points",
     false},
    {"Tracks", "tracksToggle", "route", "tracks", "show_backend_calculated_tracks", false},
    {:flights, "flightsToggle", "plane", "flights",
     "show_airtrail_flights_as_arcs_hides_overlapping_gps", false},
    {"Visits", "visitsToggle", "map-pin-check", "visits", "show_detected_area_visits", false},
    {"Places", "placesToggle", "map-pin", "places", "show_your_saved_places", false},
    {"Areas", "areasToggle", "square-dashed-mouse-pointer", "areas", "show_defined_areas", false},
    {"Photos", "photosToggle", "image", "photos", "show_geotagged_photos", false},
    {"Heatmap", "heatmapToggle", "flame", "heatmap", "show_density_heatmap", true},
    {"Hexagons", "hexagonsToggle", "hexagon", "hexagons", "show_point_density_as_hexagonal_cells",
     true},
    {"Fog of War", "fogToggle", "cloud-fog", "fog_of_war", "show_explored_areas", true},
    {"Scratch map", "scratchToggle", "flag", "scratch_map", "show_scratched_countries", true}
  ]

  attr :locale, :string, required: true
  attr :panel, :string, required: true
  attr :settings, :map, default: nil
  attr :config, :map, required: true
  attr :page, :map, required: true

  def tab(assigns) do
    enabled = (assigns.settings && assigns.settings.saved["enabled_map_layers"]) || []
    restricted = !!(assigns.settings && assigns.settings.restricted)
    filters = assigns.settings && assigns.settings.saved["places_tag_filters"]
    choices = ["untagged" | Enum.map(assigns.page.tags, & &1.id)]

    tiles =
      for {layer, target, icon, key, description, pro} <- @tiles,
          layer != :flights or assigns.config["airtrailConfigured"] do
        %{
          layer: layer,
          target: target,
          icon: icon,
          key: key,
          description: description,
          pro: pro,
          checked:
            if(layer == :flights, do: !!assigns.config["flightsEnabled"], else: layer in enabled)
        }
      end

    assigns =
      assign(assigns,
        tiles: tiles,
        restricted: restricted,
        tag_checked: &(is_nil(filters) or &1 in filters),
        all_tags: is_nil(filters) or Enum.sort(filters) == Enum.sort(choices)
      )

    ~H"""
    <div
      id="native-map-layers"
      class={["tab-content", @panel in ["", "layers"] && "active"]}
      data-tab-content="layers"
    >
      <div class="layer-tiles">
        <label :for={tile <- @tiles} class="layer-tile" title={p(@locale, tile.description)}>
          <input
            type="checkbox"
            class="layer-tile__input"
            aria-describedby={"layer-tile-#{tile.target}-description"}
            data-maps--maplibre-target={tile.target}
            checked={tile.checked}
            disabled={@restricted && tile.pro}
            data-map-layer={tile.key}
            data-testid={"map-layer-" <> tile.key}
            phx-click={if(tile.layer == :flights, do: "map:flights", else: "settings:layer")}
            phx-value-layer={if(tile.layer != :flights, do: tile.layer)}
            phx-value-enabled={to_string(!tile.checked)}
          />
          <Icon.icon name={tile.icon} class="layer-tile__icon" />
          <span class="layer-tile__label">{p(@locale, tile.key)}</span>
          <span id={"layer-tile-#{tile.target}-description"} class="sr-only">{p(
            @locale,
            tile.description
          )}</span>
          <span :if={tile.pro && @restricted} class="layer-tile__badge">
            <DawarichWeb.MapParts.pro_badge restricted url={@page.badge_url} locale={@locale} />
          </span>
        </label>
      </div>

      <div class="layer-options">
        <div class="layer-options__group space-y-2" data-layer-options="points">
          <span class="layer-options__label">{p(@locale, "points")}</span>
          <label class="label cursor-pointer justify-start gap-3 py-0">
            <input
              type="checkbox"
              class="toggle toggle-warning toggle-sm"
              data-map-layer="anomalies"
              data-testid="map-layer-anomalies"
              checked={@config["anomaliesPreferred"]}
              phx-click="map:anomalies"
              phx-value-enabled={to_string(!@config["anomaliesPreferred"])}
            />
            <span class="label-text">{p(@locale, "anomalies")}</span>
          </label>
          <p class="text-sm text-base-content/60">{p(@locale, "show_filtered_gps_noise_points")}</p>
          <label
            class={["label cursor-pointer justify-start gap-3 py-0", @restricted && "opacity-40"]}
            {if(@restricted, do: [style: "cursor: not-allowed;"], else: [])}
          >
            <input
              type="checkbox"
              class="toggle toggle-primary toggle-sm"
              data-testid="native-edit-points"
              disabled={@restricted}
              checked={@config["editEnabled"]}
              phx-click="settings:point_edit"
              phx-value-enabled={to_string(!@config["editEnabled"])}
            />
            <span class="label-text">{p(@locale, "edit_points")}</span>
          </label>
          <%= if @restricted do %>
            <p class="text-sm text-base-content/60 mt-1">
              {p(
                @locale,
                "allow_dragging_points_to_correct_their_position"
              )}
            </p>
            <p class="text-xs text-warning mt-1">
              {p(
                @locale,
                "editing_points_is_a_pro_feature_this_stays_on_for"
              )}
            </p>
          <% else %>
            <p class="text-sm text-base-content/60 mt-1">
              {p(
                @locale,
                "allow_dragging_points_to_correct_their_position_remembered_across_sessio"
              )}
            </p>
          <% end %>
          <p class="text-xs text-warning mt-1 hidden" data-map-edit-unavailable></p>
        </div>

        <div class="layer-options__group" data-layer-options="fog">
          <span class="layer-options__label">{p(@locale, "fog_of_war")}</span>
          <div class="flex flex-wrap gap-4">
            <label
              :for={{mode, key} <- [{"points", "per_point"}, {"hexagons", "per_hexagon"}]}
              class="label cursor-pointer gap-2 py-0"
            >
              <input
                type="radio"
                name="fogOfWarMode"
                value={mode}
                class="radio radio-sm"
                checked={(@config["fogMode"] || "points") == mode}
                phx-click="settings:fog_mode"
                phx-value-mode={mode}
              />
              <span class="label-text text-sm">{p(@locale, key)}</span>
            </label>
          </div>
        </div>

        <div
          class="layer-options__group space-y-2"
          {if(@config["visitsEnabled"], do: [], else: [style: "display: none;"])}
        >
          <span class="layer-options__label">{p(@locale, "visits")}</span>
          <input
            type="text"
            id="visits-search"
            placeholder={p(@locale, "filter_by_name")}
            class="input input-sm input-bordered w-full"
            form="native-map-visit-filter"
            name="query"
            value={get_in(@config, ["visitFilter", "query"])}
            phx-debounce="300"
          />
          <select
            class="select select-bordered select-sm w-full py-0"
            form="native-map-visit-filter"
            name="status"
          >
            <option
              :for={
                {value, key} <- [
                  {"all", "all_visits"},
                  {"confirmed", "confirmed_only"},
                  {"suggested", "suggested_only"}
                ]
              }
              value={value}
              selected={(get_in(@config, ["visitFilter", "status"]) || "all") == value}
            >
              {p(@locale, key)}
            </option>
          </select>
        </div>

        <div
          class="layer-options__group space-y-2"
          {if(@config["placesEnabled"], do: [], else: [style: "display: none;"])}
        >
          <span class="layer-options__label">{p(@locale, "places")}</span>
          <label class="label cursor-pointer justify-start gap-2 py-0">
            <input
              type="checkbox"
              class="toggle toggle-sm"
              id="native-place-tags-all"
              checked={@all_tags}
              phx-click="settings:place_tags_all"
              phx-value-enabled={to_string(!@all_tags)}
            />
            <span class="label-text text-sm">{p(@locale, "enable_all_tags")}</span>
          </label>
          <div class="flex flex-wrap gap-2">
            <.tag_badge
              value="untagged"
              color="#94a3b8"
              checked={@tag_checked.("untagged")}
              label={p(@locale, "untagged")}
            />
            <.tag_badge
              :for={tag <- @page.tags}
              value={to_string(tag.id)}
              color={tag.color}
              checked={@tag_checked.(tag.id)}
              label={"#{tag.icon} ##{tag.name}"}
              name={tag.name}
            />
          </div>
          <p class="text-xs text-base-content/60">{p(@locale, "click_tags_to_filter_places")}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :value, :string, required: true
  attr :color, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true
  attr :name, :string, default: nil

  defp tag_badge(assigns) do
    ~H"""
    <label class="cursor-pointer">
      <input
        type="checkbox"
        name="place_tag_ids[]"
        value={@value}
        class="checkbox checkbox-xs hidden peer"
        checked={@checked}
        phx-click="settings:place_tag"
        phx-value-tag={@value}
        phx-value-enabled={to_string(!@checked)}
      />
      <span
        class={["badge badge-sm transition-all peer-checked:scale-105", !@checked && "badge-outline"]}
        style={
          if(@checked,
            do: "border-color: #{@color}; color: white; background-color: #{@color};",
            else: "border-color: #{@color}; color: #{@color};"
          )
        }
        data-checked-style={"background-color: #{@color}; color: white;"}
        data-map-tag-name={@name}
      >
        {@label}
      </span>
    </label>
    """
  end

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
