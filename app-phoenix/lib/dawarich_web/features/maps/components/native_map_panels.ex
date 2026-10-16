defmodule DawarichWeb.NativeMapPanels do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  @panels [
    {"timeline", "timeline"},
    {"layers", "layers"},
    {"search", "search"},
    {"tools", "tools"},
    {"settings", "settings"},
    {"insights", "insights"}
  ]
  @layers [
    {"Points", "points"},
    {"Tracks", "tracks"},
    {"Heatmap", "heatmap"},
    {"Hexagons", "hexagons"},
    {"Scratch map", "scratch_map"},
    {"Photos", "photos"},
    {"Visits", "visits"},
    {"Places", "places"},
    {"Areas", "areas"},
    {"Family Members", "family_members"}
  ]

  @descriptions %{
    "points" => "show_individual_location_points",
    "tracks" => "show_backend_calculated_tracks",
    "heatmap" => "show_density_heatmap",
    "hexagons" => "show_point_density_as_hexagonal_cells",
    "photos" => "show_geotagged_photos",
    "visits" => "show_detected_area_visits",
    "places" => "show_your_saved_places",
    "areas" => "show_defined_areas",
    "scratch_map" => "show_scratched_countries"
  }

  def layers, do: ["Fog of War" | Enum.map(@layers, &elem(&1, 0))]

  attr :locale, :string, required: true
  attr :panel, :string, default: ""

  attr :self_hosted, :boolean, default: true

  attr :family, :boolean, default: false

  def navigation(assigns) do
    panels = if assigns.self_hosted, do: @panels, else: @panels ++ [{"links", "links"}]
    panels = if assigns.family, do: panels ++ [{"family", "family"}], else: panels
    assigns = assign(assigns, :panels, panels)

    ~H"""
    <nav class="flex min-w-0 flex-wrap gap-2" aria-label={c(@locale, "map_controls")}>
      <button
        :for={{panel, button} <- @panels}
        type="button"
        class="btn btn-sm h-auto whitespace-normal"
        data-testid={"map-button-#{button}"}
        phx-click="map:panel"
        phx-value-panel={panel}
        phx-value-toggle="true"
        aria-expanded={to_string(@panel == panel)}
        aria-controls={
          %{
            "timeline" => "native-map-panel",
            "layers" => "native-map-layers-panel",
            "settings" => "native-map-settings",
            "family" => "native-map-family-panel"
          }[panel]
        }
      >
        {c(@locale, button)}
      </button>
      <button
        :if={@panel != ""}
        id="native-map-panel-close"
        type="button"
        class="btn btn-sm"
        phx-click="map:panel"
        phx-value-panel=""
        aria-label={t(@locale, "javascript.common.close", %{})}
      >
        {t(@locale, "javascript.common.close", %{})}
      </button>
    </nav>
    """
  end

  attr :locale, :string, required: true
  attr :settings, :map, required: true
  attr :config, :map, required: true

  def layer_panel(assigns) do
    assigns =
      assign(assigns,
        layers: Enum.reject(@layers, &(elem(&1, 0) == "Family Members")),
        descriptions: @descriptions
      )

    ~H"""
    <section id="native-map-layers-panel" class="w-full min-w-0 max-w-96 bg-base-100 p-3">
      <form id="native-map-layers" phx-change="settings:map_layers" class="space-y-2">
        <input type="hidden" name="layers[]" value="" />
        <label :for={{name, key} <- @layers} class="flex min-w-0 flex-wrap items-center gap-2">
          <input
            type="checkbox"
            class="toggle toggle-primary"
            name="layers[]"
            value={name}
            checked={name in @settings.saved["enabled_map_layers"]}
            data-map-layer={key}
            data-testid={"map-layer-" <> key}
            disabled={@settings.restricted && name in ["Heatmap", "Fog of War", "Scratch map"]}
          />
          <span class="min-w-0 [overflow-wrap:anywhere]">{t(
            @locale,
            "map.maplibre.settings_panel." <> key,
            %{}
          )}</span>
          <span class="text-xs text-base-content/60 w-full">{t(
            @locale,
            "map.maplibre.settings_panel." <> @descriptions[key],
            %{}
          )}</span>
        </label>
        <fieldset class="space-y-2" disabled={@settings.restricted}>
          <legend>{t(@locale, "map.maplibre.settings_panel.fog_of_war", %{})}</legend>
          <label class="flex items-center gap-2">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              name="layers[]"
              value="Fog of War"
              checked={"Fog of War" in @settings.saved["enabled_map_layers"]}
            />
            {t(@locale, "map.maplibre.settings_panel.show_explored_areas", %{})}
          </label>
          <label
            :for={{mode, key} <- [{"points", "per_point"}, {"hexagons", "per_hexagon"}]}
            class="inline-flex items-center gap-2 mr-3"
          >
            <input
              type="radio"
              class="radio radio-sm"
              name="fog_mode"
              value={mode}
              checked={@config["fogMode"] == mode}
            />
            {t(@locale, "map.maplibre.settings_panel." <> key, %{})}
          </label>
        </fieldset>
      </form>
      <form
        :if={@config["visitsEnabled"]}
        id="native-map-visit-filter"
        phx-change="map:visits_filter"
        class="space-y-2 mt-3"
      >
        <input
          type="search"
          class="input input-sm input-bordered w-full"
          name="query"
          value={get_in(@config, ["visitFilter", "query"])}
          aria-label={t(@locale, "map.maplibre.settings_panel.filter_by_name", %{})}
        />
        <select
          name="status"
          class="select select-bordered w-full"
          aria-label={t(@locale, "map.maplibre.settings_panel.visits", %{})}
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
            {t(@locale, "map.maplibre.settings_panel." <> key, %{})}
          </option>
        </select>
      </form>
      <label :if={@config["airtrailConfigured"]} class="flex items-center gap-2 mt-2">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          data-map-layer="flights"
          checked={@config["flightsEnabled"]}
          phx-click="map:flights"
          phx-value-enabled={to_string(!@config["flightsEnabled"])}
        />
        {t(@locale, "map.maplibre.settings_panel.flights", %{})}
        <span class="text-xs text-base-content/60">{t(
          @locale,
          "map.maplibre.settings_panel.show_airtrail_flights_as_arcs_hides_overlapping_gps",
          %{}
        )}</span>
      </label>
      <label class="flex min-w-0 flex-wrap items-center gap-2">
        <input
          type="checkbox"
          class="toggle toggle-warning"
          data-map-layer="anomalies"
          data-testid="map-layer-anomalies"
          checked={@config["anomaliesPreferred"]}
          disabled={!@config["pointsEnabled"]}
          phx-click="map:anomalies"
          phx-value-enabled={to_string(!@config["anomaliesPreferred"])}
        />
        <span>{t(@locale, "map.maplibre.settings_panel.anomalies", %{})}</span>
      </label>
    </section>
    """
  end

  defp c(locale, "insights"), do: t(locale, "shared.navbar.insights_sup_sup_html", %{})
  defp c(locale, key), do: t(locale, "map.maplibre.button_cluster." <> key, %{})
end
