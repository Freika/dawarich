import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadModule(relativePath, dependencies = "") {
  const source = await readFile(new URL(relativePath, import.meta.url), "utf8")
  const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const url = `data:text/javascript;base64,${Buffer.from(
    `${dependencies}\n${withoutImports}`,
  ).toString("base64")}`

  return import(url)
}

const { PhotosLayer } = await loadModule(
  "../../app/javascript/maps_maplibre/layers/photos_layer.js",
  `
    const translate = (key) => key
    const formatTimestamp = (value) => String(value)
    const getCurrentTheme = () => "light"
    const getThemeColors = () => ({})
    const escapeHtml = (value) => String(value ?? "")
    const escapeAttribute = escapeHtml
    class PhotoClusterGallery {}
    class BaseLayer {}
    const maplibregl = {
      Marker: class {
        setLngLat(lngLat) { this.lngLat = lngLat; return this }
        addTo() { return this }
        remove() {}
      },
    }
  `,
)

// A photo enriched over the North Pole (issue #3262).
const PHOTO = { id: "polar-photo", lng: 40, lat: 89.9 }

// MapLibre's GeoJSON source projects points to Web Mercator in its worker and
// clamps y to [0, 1] (geojson-vt projectY), so querySourceFeatures hands back
// the tile geometry at the Mercator limit, not the photo's real latitude.
// Observed with @maplibre/geojson-vt Supercluster.getTile for [40, 89.9].
const MERCATOR_LIMIT_LAT = 85.0511

function polarLayer(projection, ids = [PHOTO.id]) {
  const layer = Object.create(PhotosLayer.prototype)
  layer.visible = true
  layer.sourceId = "photos-source"
  layer.markerCache = new Map()
  layer.legCache = new Map()
  layer.data = {
    type: "FeatureCollection",
    features: ids.map((id) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: [PHOTO.lng, PHOTO.lat] },
      properties: { id, thumbnail_url: "/thumb.jpg" },
    })),
  }
  layer.map = {
    getSource: () => ({}),
    getProjection: () => projection,
    querySourceFeatures: () =>
      ids.map((id) => ({
        geometry: {
          type: "Point",
          coordinates: [PHOTO.lng, MERCATOR_LIMIT_LAT],
        },
        properties: { id, thumbnail_url: "/thumb.jpg" },
      })),
    getBounds: () => ({ contains: () => true }),
    project: ([lng, lat]) => ({ x: lng, y: lat }),
    unproject: ([x, y]) => ({ lng: x, lat: y }),
  }
  globalThis.document = {
    createElement: () => ({
      style: {},
      addEventListener() {},
      appendChild() {},
    }),
  }
  return layer
}

function syncedMarkerLngLat(projection) {
  const layer = polarLayer(projection)
  layer._syncMarkers()
  const marker = layer.markerCache.get(PHOTO.id)
  assert.ok(marker, "expected a marker for the polar photo")
  return marker.lngLat
}

test("on the globe a photo near the pole keeps its real latitude", () => {
  const [lng, lat] = syncedMarkerLngLat({ type: "globe" })
  assert.equal(lng, PHOTO.lng)
  assert.equal(
    lat,
    PHOTO.lat,
    `marker drawn at ${lat}°N instead of the photo's ${PHOTO.lat}°N`,
  )
})

test("on the flat map a photo near the pole stays at the Mercator limit", () => {
  // At 89.9° the marker would sit above the top edge of the Mercator world.
  for (const projection of [undefined, { type: "mercator" }]) {
    const [lng, lat] = syncedMarkerLngLat(projection)
    assert.equal(lng, PHOTO.lng)
    assert.equal(lat, MERCATOR_LIMIT_LAT)
  }
})

test("on the globe overlapping polar photos spread around their real latitude", () => {
  const layer = polarLayer({ type: "globe" }, ["polar-a", "polar-b"])

  layer._syncMarkers()

  const lats = ["polar-a", "polar-b"].map(
    (id) => layer.markerCache.get(id).lngLat[1],
  )
  const centerLat = (lats[0] + lats[1]) / 2
  assert.ok(
    Math.abs(centerLat - PHOTO.lat) < 1e-9,
    `spread centred on ${centerLat}°N instead of the photos' ${PHOTO.lat}°N`,
  )
})
