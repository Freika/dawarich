defmodule DawarichWeb.NativeMapPanels do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  @panels [
    {"timeline", "timeline"},
    {"layers", "layers"},
    {"search", "search"},
    {"tools", "create"},
    {"settings", "settings"},
    {"insights", "insights"}
  ]
  @layers [
    {"Points", "points"},
    {"Tracks", "tracks"},
    {"Heatmap", "heatmap"},
    {"Hexagons", "hexagons"},
    {"Fog of War", "fog_of_war"},
    {"Scratch map", "scratch_map"},
    {"Photos", "photos"},
    {"Visits", "visits"},
    {"Places", "places"},
    {"Areas", "areas"}
  ]

  def layers, do: Enum.map(@layers, &elem(&1, 0))

  attr :locale, :string, required: true
  attr :panel, :string, default: ""

  def navigation(assigns) do
    assigns = assign(assigns, :panels, @panels)

    ~H"""
    <nav class="flex min-w-0 flex-wrap gap-2" aria-label={c(@locale, "map_controls")}>
      <button
        :for={{panel, button} <- @panels}
        type="button"
        class="btn btn-sm h-auto whitespace-normal"
        data-testid={"map-button-#{button}"}
        phx-click="map:panel"
        phx-value-panel={panel}
        aria-expanded={to_string(@panel == panel)}
        aria-controls={
          %{
            "timeline" => "native-map-panel",
            "layers" => "native-map-layers-panel",
            "settings" => "native-map-settings"
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
        aria-label={t(@locale, "common.close", %{})}
      >
        {t(@locale, "common.close", %{})}
      </button>
    </nav>
    """
  end

  attr :locale, :string, required: true
  attr :settings, :map, required: true
  attr :config, :map, required: true

  def layer_panel(assigns) do
    assigns = assign(assigns, :layers, @layers)

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
            disabled={@settings.restricted && name in ["Heatmap", "Fog of War", "Scratch map"]}
          />
          <span class="min-w-0 [overflow-wrap:anywhere]">{t(
            @locale,
            "map.maplibre.settings_panel." <> key,
            %{}
          )}</span>
        </label>
      </form>
      <label class="flex min-w-0 flex-wrap items-center gap-2">
        <input
          type="checkbox"
          class="toggle toggle-warning"
          data-map-layer="anomalies"
          checked={@config["anomaliesEnabled"]}
          phx-click="map:anomalies"
          phx-value-enabled={to_string(!@config["anomaliesEnabled"])}
        />
        <span>{t(@locale, "map.maplibre.settings_panel.anomalies", %{})}</span>
      </label>
    </section>
    """
  end

  defp c(locale, "insights"), do: t(locale, "navbar.insights", %{})
  defp c(locale, key), do: t(locale, "map.maplibre.button_cluster." <> key, %{})
end
