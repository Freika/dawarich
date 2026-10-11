import { createRequestScope } from "../data/request_scope.js"
import { applyMapStyle } from "../style/map_style.js"
import { createStyleControls } from "./style_controls.js"

export function mapSettings(settings, config) {
  const maps = settings.maps ?? {}
  const enabled = settings.enabled_map_layers
  const styleName = settings.maps_maplibre_style
  return {
    ...config,
    routeOptions: {
      ...config.routeOptions,
      distanceThresholdMeters: Number(settings.meters_between_routes ?? config.routeOptions?.distanceThresholdMeters),
      timeThresholdMinutes: Number(settings.minutes_between_routes ?? config.routeOptions?.timeThresholdMinutes),
    },
    distanceUnit: maps.distance_unit ?? config.distanceUnit,
    customTheme: settings.maps_maplibre_custom_theme ?? config.customTheme,
    tilesFallback:
      settings.maps_maplibre_tiles_fallback ?? config.tilesFallback,
    tilesUrl: settings.maps_maplibre_tiles_url ?? config.tilesUrl,
    hiddenTileCategories:
      maps.hidden_tile_categories ?? config.hiddenTileCategories,
    disabledPoiGroups: maps.disabled_poi_groups ?? config.disabledPoiGroups,
    mapOptions: {
      ...config.mapOptions,
      projection: {
        type: settings.globe_projection === true ? "globe" : "mercator",
      },
    },
    styleName: styleName ?? config.styleName,
    styleUrl: `/maps_maplibre/styles/${["light", "dark", "white", "black", "grayscale"].includes(styleName) ? styleName : "light"}.json`,
    trackColor: settings.track_color ?? config.trackColor,
    pointsEnabled: enabled ? enabled.includes("Points") : config.pointsEnabled,
    tracksEnabled: enabled ? enabled.includes("Tracks") : config.tracksEnabled,
    heatmapEnabled: enabled
      ? enabled.includes("Heatmap")
      : config.heatmapEnabled,
    editEnabled: settings.point_dragging_enabled ?? config.editEnabled,
  }
}

export function createHostSettings({
  map,
  loadStyle,
  lifetime,
  getConfig,
  update,
  onError,
}) {
  const scope = createRequestScope()
  lifetime.own(() => scope.destroy())
  const readStyle = async (url) => {
    const operation = scope.begin()
    try {
      return applyMapStyle(
        await operation.wait(
          loadStyle(
            { ...getConfig(), styleUrl: url },
            { signal: operation.signal },
          ),
        ),
        getConfig(),
      )
    } finally {
      operation.close()
    }
  }
  const style = createStyleControls({
    map,
    defaultStyleUrl: "/maps_maplibre/styles/light.json",
    loadStyle: readStyle,
    onFallback: onError,
  })
  lifetime.own(style.destroy)
  return async ({ settings }) => {
    const previous = getConfig()
    const next = mapSettings(settings, previous)
    await update(next)
    const appearance = (config) =>
      JSON.stringify([
        config.styleUrl,
        config.customTheme,
        config.tilesUrl,
        config.hiddenTileCategories,
        config.disabledPoiGroups,
      ])
    if (appearance(next) !== appearance(previous))
      await style.apply(next.styleUrl)
  }
}
