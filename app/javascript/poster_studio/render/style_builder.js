import {
  DEFAULT_TILE_URL,
  PARK_KINDS,
  ROAD_BUCKETS,
  SOURCE_ID,
  SOURCE_MAX_ZOOM,
} from "../data/protomaps_schema.js"

export const TRACK_SOURCE_ID = "poster-track"

const EMPTY_FC = { type: "FeatureCollection", features: [] }

function zoomInterp(stops, scale = 1) {
  const flat = stops.flatMap(([z, w]) => [z, w * scale])
  return ["interpolate", ["linear"], ["zoom"], ...flat]
}

// Buildings, railways, and admin boundaries are live-map extras: the poster
// look (preview + export) deliberately stays without them for sidecar parity.
function buildExtraLayers(theme) {
  return {
    buildings: {
      id: "poster_buildings",
      type: "fill",
      source: SOURCE_ID,
      "source-layer": "buildings",
      filter: ["in", "kind", "building", "building_part"],
      paint: { "fill-color": theme.buildings },
    },
    railways: {
      id: "poster_railways",
      type: "line",
      source: SOURCE_ID,
      "source-layer": "roads",
      filter: ["==", "kind", "rail"],
      paint: {
        "line-color": theme.railway,
        "line-width": zoomInterp([
          [8, 0.4],
          [12, 0.9],
          [16, 2],
        ]),
      },
    },
    boundaries: {
      id: "poster_boundaries",
      type: "line",
      source: SOURCE_ID,
      "source-layer": "boundaries",
      filter: ["<=", "kind_detail", 4],
      paint: {
        "line-color": theme.boundaries,
        "line-width": zoomInterp([
          [3, 0.5],
          [8, 1],
          [12, 1.6],
        ]),
        "line-dasharray": [3, 2],
      },
    },
  }
}

// Maps the user's base-map category toggles onto the minimal basemap's own
// layers. Label/POI categories have no counterpart here and are ignored.
const LAYER_CATEGORIES = {
  poster_parks: "landuse",
  poster_water: "water",
  poster_water_lines: "water",
  poster_buildings: "buildings",
  poster_railways: "rail",
  poster_boundaries: "boundaries",
}

export function buildBasemapStyle({
  theme,
  tileUrl = DEFAULT_TILE_URL,
  roadScale = 1,
  extras = false,
  hiddenCategories = [],
}) {
  if (!theme) throw new Error("buildBasemapStyle requires a resolved theme")

  const visible = (layer) =>
    !hiddenCategories.includes(LAYER_CATEGORIES[layer.id])

  const extraLayers = extras ? buildExtraLayers(theme) : null

  const roadLayers = hiddenCategories.includes("roads")
    ? []
    : ROAD_BUCKETS.map((bucket) => ({
        id: bucket.id,
        type: "line",
        source: SOURCE_ID,
        "source-layer": "roads",
        filter: bucket.filter,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": theme.roads[bucket.themeKey] ?? theme.roads.default,
          "line-width": zoomInterp(bucket.widthStops, roadScale),
        },
      }))

  return {
    version: 8,
    sources: {
      [SOURCE_ID]: {
        type: "vector",
        tiles: [tileUrl],
        maxzoom: SOURCE_MAX_ZOOM,
        attribution:
          '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>',
      },
    },
    layers: [
      {
        id: "poster_bg",
        type: "background",
        paint: { "background-color": theme.bg },
      },
      {
        id: "poster_earth",
        type: "fill",
        source: SOURCE_ID,
        "source-layer": "earth",
        paint: { "fill-color": theme.bg },
      },
      {
        id: "poster_parks",
        type: "fill",
        source: SOURCE_ID,
        "source-layer": "landuse",
        filter: ["in", "kind", ...PARK_KINDS],
        paint: { "fill-color": theme.parks },
      },
      {
        id: "poster_water",
        type: "fill",
        source: SOURCE_ID,
        "source-layer": "water",
        filter: ["==", "$type", "Polygon"],
        paint: { "fill-color": theme.water },
      },
      {
        id: "poster_water_lines",
        type: "line",
        source: SOURCE_ID,
        "source-layer": "water",
        filter: ["in", "kind", "river", "stream"],
        paint: {
          "line-color": theme.water,
          "line-width": zoomInterp([
            [8, 0.4],
            [12, 0.9],
            [16, 2.2],
          ]),
        },
      },
      ...(extraLayers ? [extraLayers.buildings] : []),
      ...roadLayers,
      ...(extraLayers ? [extraLayers.railways, extraLayers.boundaries] : []),
    ].filter(visible),
  }
}

export function buildPosterStyle({
  theme,
  trackGeojson = EMPTY_FC,
  tileUrl = DEFAULT_TILE_URL,
  roadScale = 1,
  trackWidth = 1,
  trackColor = null,
  trackOpacity = 1,
  extras = false,
  hiddenCategories = [],
}) {
  const style = buildBasemapStyle({
    theme,
    tileUrl,
    roadScale,
    extras,
    hiddenCategories,
  })

  return {
    ...style,
    sources: {
      ...style.sources,
      [TRACK_SOURCE_ID]: { type: "geojson", data: trackGeojson },
    },
    layers: [
      ...style.layers,
      {
        id: "poster_track_casing",
        type: "line",
        source: TRACK_SOURCE_ID,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": theme.casing,
          "line-opacity": trackOpacity,
          "line-width": zoomInterp(
            [
              [8, 3.2],
              [12, 4.6],
              [16, 7],
            ],
            trackWidth,
          ),
        },
      },
      {
        id: "poster_track",
        type: "line",
        source: TRACK_SOURCE_ID,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": trackColor || theme.route,
          "line-opacity": trackOpacity,
          "line-width": zoomInterp(
            [
              [8, 1.5],
              [12, 2.6],
              [16, 4.6],
            ],
            trackWidth,
          ),
        },
      },
    ],
  }
}
