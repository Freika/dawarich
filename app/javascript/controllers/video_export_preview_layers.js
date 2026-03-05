/**
 * MapLibre layer management helpers for the video export preview.
 * Handles route line, marker sources/layers, and the arrow marker element.
 */

import maplibregl from "maplibre-gl"

export const ROUTE_SOURCE = "preview-route"
export const ROUTE_LAYER = "preview-route-line"
export const MARKER_SOURCE = "preview-marker"
export const MARKER_GLOW_LAYER = "preview-marker-glow"
export const MARKER_LAYER = "preview-marker-solid"

export function buildGradient(color) {
  return [
    "interpolate",
    ["linear"],
    ["line-progress"],
    0,
    `${color}33`,
    1,
    color,
  ]
}

function clearSources(map) {
  if (map.getSource(ROUTE_SOURCE)) {
    if (map.getLayer(ROUTE_LAYER)) map.removeLayer(ROUTE_LAYER)
    map.removeSource(ROUTE_SOURCE)
  }
  if (map.getSource(MARKER_SOURCE)) {
    if (map.getLayer(MARKER_GLOW_LAYER)) map.removeLayer(MARKER_GLOW_LAYER)
    if (map.getLayer(MARKER_LAYER)) map.removeLayer(MARKER_LAYER)
    map.removeSource(MARKER_SOURCE)
  }
}

export function addRouteLayers(map, coords, { routeColor, routeWidth }) {
  clearSources(map)

  map.addSource(ROUTE_SOURCE, {
    type: "geojson",
    data: {
      type: "Feature",
      geometry: {
        type: "LineString",
        coordinates: coords.map((c) => [c.lon, c.lat]),
      },
    },
    lineMetrics: true,
  })

  map.addLayer({
    id: ROUTE_LAYER,
    type: "line",
    source: ROUTE_SOURCE,
    layout: { "line-join": "round", "line-cap": "round" },
    paint: {
      "line-width": routeWidth,
      "line-gradient": buildGradient(routeColor),
    },
  })

  const start = coords[0]
  map.addSource(MARKER_SOURCE, {
    type: "geojson",
    data: {
      type: "Feature",
      geometry: { type: "Point", coordinates: [start.lon, start.lat] },
    },
  })
}

export function addDotLayers(map, markerColor) {
  if (map.getLayer(MARKER_GLOW_LAYER)) map.removeLayer(MARKER_GLOW_LAYER)
  if (map.getLayer(MARKER_LAYER)) map.removeLayer(MARKER_LAYER)

  map.addLayer({
    id: MARKER_GLOW_LAYER,
    type: "circle",
    source: MARKER_SOURCE,
    paint: {
      "circle-radius": 14,
      "circle-color": markerColor,
      "circle-opacity": 0.3,
    },
  })

  map.addLayer({
    id: MARKER_LAYER,
    type: "circle",
    source: MARKER_SOURCE,
    paint: {
      "circle-radius": 8,
      "circle-color": markerColor,
      "circle-stroke-width": 3,
      "circle-stroke-color": "#ffffff",
    },
  })
}

function createArrowElement(color) {
  const el = document.createElement("div")
  el.style.cssText =
    "width:0;height:0;border-left:6px solid transparent;border-right:6px solid transparent;" +
    `border-bottom:14px solid ${color};` +
    "filter:drop-shadow(0 0 4px rgba(0,0,0,0.4));transform-origin:center center;"
  return el
}

export function addArrowMarker(map, coords, markerColor) {
  if (map.getLayer(MARKER_GLOW_LAYER)) map.removeLayer(MARKER_GLOW_LAYER)
  if (map.getLayer(MARKER_LAYER)) map.removeLayer(MARKER_LAYER)

  const start = coords[0]
  return new maplibregl.Marker({ element: createArrowElement(markerColor) })
    .setLngLat([start.lon, start.lat])
    .addTo(map)
}

export function extractCoordsFromGeoJSON(geojson) {
  if (!geojson?.features?.length) return null

  for (const feature of geojson.features) {
    const rawCoords = feature.geometry?.coordinates
    if (!rawCoords?.length || rawCoords.length < 2) continue

    const startAt = feature.properties?.start_at
    const endAt = feature.properties?.end_at
    const startTs = startAt ? new Date(startAt).getTime() / 1000 : 0
    const endTs = endAt
      ? new Date(endAt).getTime() / 1000
      : startTs + rawCoords.length * 10

    return rawCoords.map((c, i) => ({
      lon: c[0],
      lat: c[1],
      timestamp: startTs + ((endTs - startTs) * i) / (rawCoords.length - 1),
    }))
  }
  return null
}
