import { createRequestScope } from "../data/request_scope.js"
import { createStyleControls } from "./style_controls.js"

export function mapSettings(settings, config) {
  return {
    ...config,
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
    try { return await operation.wait(loadStyle({ ...getConfig(), styleUrl: url }, {signal: operation.signal})) }
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
