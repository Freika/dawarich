const MATCHED_POLYLINE6 =
  "mttdcBceuqXhHtPvKlUz@qA`I_MvF`O|@zJz@~JD|AzCxGdDlHv@uAlFpLTh@^|@v@lBb@fAxApD|@wAv[|z@hShi@zB`GfLrZlTrk@NrBf@`HRbC|HnT`@dAv@zBjBtKzA`ExJ`XjFrN^z@bAbCh@pAl@xAl@xAjApCj@rA~@{@~a@xqAj\\ldArBkC~BlH^lAbLz^hBhG~AhFrHbVbJhZp@xBhBvGz@nElAfGp@~BZhAlC~IlBx@nBzF?dEhF~Q|@tCj@rCJbBI`B]hAs@vA_InK[hDyBxBq@DQRqh@dn@_JbMyM`ReGnHs@z@qB~BRjCh@pNvAfm@JlER`H`Ah_@nCleARxHBx@NlGzAxk@L`FRxHHjD`Bvm@tAxg@J`DHpAF~@PdBXhBf@lCb@lBZbBRnBH|A~@n\\FnB`Ap]dAt_@jApa@BjAPhGNvFH|C~@n]l@dUlAtd@BjATjIThJJlD`Bhn@t@dYnBru@|@l]DdAVrJXlJHzCt@dZ^`NhAzc@R|HBt@NpFLbFD`AXdKDrBRdHp@fVP`GbAv_@bAh^h@xRfA|`@ThKRdI_C|@yAh@{@Zu@XjAfg@z@Gv@hXFpCHxCtCbdAHrCt@|K\\vMBzADhB"

function decodePolyline6(encoded) {
  const coordinates = []
  let index = 0
  let latitude = 0
  let longitude = 0

  while (index < encoded.length) {
    const deltas = []

    for (let axis = 0; axis < 2; axis += 1) {
      let result = 0
      let shift = 0
      let byte

      do {
        byte = encoded.charCodeAt(index) - 63
        index += 1
        result |= (byte & 0x1f) << shift
        shift += 5
      } while (byte >= 0x20)

      deltas.push(result & 1 ? ~(result >> 1) : result >> 1)
    }

    latitude += deltas[0]
    longitude += deltas[1]
    coordinates.push([longitude / 1_000_000, latitude / 1_000_000])
  }

  return coordinates
}

export const MATCHED_PATH = decodePolyline6(MATCHED_POLYLINE6)

export const ORIGINAL_PATH = [
  [13.413474, 52.521815],
  [13.412965, 52.521176],
  [13.411817, 52.520719],
  [13.410784, 52.520135],
  [13.409646, 52.519562],
  [13.408399, 52.5191],
  [13.40723, 52.518558],
  [13.406137, 52.517998],
  [13.404893, 52.517514],
  [13.403868, 52.516966],
  [13.402649, 52.516456],
  [13.401397, 52.516022],
  [13.400381, 52.516603],
  [13.399502, 52.517321],
  [13.398322, 52.517542],
  [13.396859, 52.517423],
  [13.39539, 52.517329],
  [13.393916, 52.517273],
  [13.392481, 52.517084],
  [13.391013, 52.516988],
  [13.389538, 52.516931],
  [13.388075, 52.51681],
  [13.386606, 52.516722],
  [13.385132, 52.516664],
  [13.383668, 52.51654],
  [13.382199, 52.516451],
  [13.380907, 52.516432],
  [13.379527, 52.516423],
  [13.378055, 52.516322],
  [13.377699, 52.51627],
]

function lineFeature(coordinates) {
  return {
    type: "Feature",
    properties: {},
    geometry: { type: "LineString", coordinates },
  }
}

export function mountDemoMap(container, maplibre, style, onReady) {
  const map = new maplibre.Map({
    container,
    style,
    center: [13.3954, 52.5185],
    zoom: 14,
    attributionControl: false,
    scrollZoom: false,
    dragRotate: false,
    pitchWithRotate: false,
  })
  map.addControl(
    new maplibre.NavigationControl({ showCompass: false }),
    "top-right",
  )
  map.addControl(
    new maplibre.AttributionControl({ compact: true }),
    "bottom-right",
  )
  map.on("load", () => {
    addDemoLayers(map, maplibre)
    onReady()
  })
  return map
}

export function addDemoLayers(map, maplibre) {
  map.addSource("map-matching-demo-original", {
    type: "geojson",
    data: lineFeature(ORIGINAL_PATH),
  })
  map.addSource("map-matching-demo-matched", {
    type: "geojson",
    data: lineFeature(MATCHED_PATH),
  })
  map.addSource("map-matching-demo-endpoints", {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [ORIGINAL_PATH[0], ORIGINAL_PATH.at(-1)].map((coordinates) => ({
        type: "Feature",
        properties: {},
        geometry: { type: "Point", coordinates },
      })),
    },
  })

  addRouteLayer(map, "matched-halo", "matched", {
    "line-color": "#ffffff",
    "line-width": 9,
    "line-opacity": 0.9,
  })
  addRouteLayer(map, "matched", "matched", {
    "line-color": "#0d9488",
    "line-width": 5,
    "line-opacity": 1,
  })
  addRouteLayer(map, "original-halo", "original", {
    "line-color": "#ffffff",
    "line-width": 8,
    "line-opacity": 0,
  })
  addRouteLayer(map, "original", "original", {
    "line-color": "#f59e0b",
    "line-width": 4,
    "line-dasharray": [1.1, 1.1],
    "line-opacity": 0.9,
  })
  map.addLayer({
    id: "map-matching-demo-endpoints",
    type: "circle",
    source: "map-matching-demo-endpoints",
    paint: {
      "circle-radius": 5,
      "circle-color": "#0d9488",
      "circle-stroke-color": "#ffffff",
      "circle-stroke-width": 3,
    },
  })

  const bounds = new maplibre.LngLatBounds()
  for (const coordinates of MATCHED_PATH) bounds.extend(coordinates)
  map.fitBounds(bounds, {
    padding: { top: 44, right: 36, bottom: 76, left: 36 },
    duration: 0,
    maxZoom: 15,
  })
}

export function showMode(map, mode) {
  const original = mode === "original"
  map.setPaintProperty(
    "map-matching-demo-original-halo",
    "line-opacity",
    original ? 0.85 : 0,
  )
  map.setPaintProperty(
    "map-matching-demo-original",
    "line-opacity",
    original ? 1 : 0.9,
  )
  map.setPaintProperty(
    "map-matching-demo-matched-halo",
    "line-opacity",
    original ? 0.25 : 0.9,
  )
  map.setPaintProperty(
    "map-matching-demo-matched",
    "line-opacity",
    original ? 0.35 : 1,
  )
}

function addRouteLayer(map, suffix, source, paint) {
  map.addLayer({
    id: `map-matching-demo-${suffix}`,
    type: "line",
    source: `map-matching-demo-${source}`,
    layout: { "line-cap": "round", "line-join": "round" },
    paint: { ...paint, "line-opacity-transition": { duration: 240, delay: 0 } },
  })
}
