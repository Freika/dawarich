import { applyMapStyle } from "../style/map_style.js"
import { createRequestScope } from "../data/request_scope.js"
import { createStyleControls } from "./style_controls.js"

export function mapSettings(settings, config) {
  const maps = settings.maps ?? {}
  return {
    ...config,
    distanceUnit: maps.distance_unit ?? config.distanceUnit,
    customTheme: settings.maps_maplibre_custom_theme ?? config.customTheme,
    tilesUrl: settings.maps_maplibre_tiles_url ?? config.tilesUrl,
    hiddenTileCategories: maps.hidden_tile_categories ?? config.hiddenTileCategories,
    disabledPoiGroups: maps.disabled_poi_groups ?? config.disabledPoiGroups,
    mapOptions: {...config.mapOptions, projection: {type: settings.globe_projection === true ? "globe" : "mercator"}},
    styleName: settings.maps_maplibre_style ?? config.styleName,
    styleUrl: `/maps_maplibre/styles/${["light", "dark", "white", "black", "grayscale"].includes(settings.maps_maplibre_style) ? settings.maps_maplibre_style : "light"}.json`,
    trackColor: settings.track_color ?? config.trackColor,
    pointsEnabled: settings.enabled_map_layers ? settings.enabled_map_layers.includes("Points") : config.pointsEnabled,
    tracksEnabled: settings.enabled_map_layers ? settings.enabled_map_layers.includes("Tracks") : config.tracksEnabled,
    heatmapEnabled: settings.enabled_map_layers ? settings.enabled_map_layers.includes("Heatmap") : config.heatmapEnabled,
    editEnabled: settings.point_dragging_enabled ?? config.editEnabled,
  }
}

export function createHostSettings({ map, loadStyle, lifetime, getConfig, update, onError }) {
  const scope = createRequestScope()
  lifetime.own(() => scope.destroy())
  const readStyle = async url => {
    const operation = scope.begin()
    try { return applyMapStyle(await operation.wait(loadStyle({ ...getConfig(), styleUrl: url }, {signal: operation.signal})), getConfig()) }
    finally { operation.close() }
  }
  const style = createStyleControls({ map, defaultStyleUrl: "/maps_maplibre/styles/light.json", loadStyle: readStyle, onFallback: onError })
  lifetime.own(style.destroy)
  return async ({ settings }) => {
    const next = mapSettings(settings, getConfig())
    await update(next)
    await style.apply(next.styleUrl)
  }
}
