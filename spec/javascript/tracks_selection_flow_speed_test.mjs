import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const toDataUrl = (code) =>
  `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`

const baseLayerSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/base_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const tracksLayerSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/tracks_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const { TracksLayer } = await import(
  toDataUrl(
    tracksLayerSource.replace(
      'import { BaseLayer } from "./base_layer"',
      `import { BaseLayer } from "${toDataUrl(baseLayerSource)}"`,
    ),
  )
)

const HIGHLIGHT = "rgba(255,255,255,0.5)"
const LATITUDE = 51.32
const FRAME_MS = 1000 / 60

function fakeMap(zoom) {
  const layers = []
  const sources = {}
  const gradients = []
  return {
    gradients,
    getStyle: () => ({ layers }),
    getLayer: (id) => layers.find((layer) => layer.id === id),
    addLayer: (config) => layers.push({ id: config.id }),
    moveLayer: () => {},
    getSource: (id) => sources[id],
    addSource: (id, spec) => {
      sources[id] = { ...spec, setData() {} }
    },
    setPaintProperty: (_id, property, value) => {
      if (property === "line-gradient") gradients.push(value)
    },
    setLayoutProperty: () => {},
    on: () => {},
    off: () => {},
    getZoom: () => zoom,
    getCenter: () => ({ lng: 12.34, lat: LATITUDE }),
  }
}

function installFrameDriver(t) {
  let pending = null
  const original = {
    raf: globalThis.requestAnimationFrame,
    caf: globalThis.cancelAnimationFrame,
  }
  globalThis.requestAnimationFrame = (callback) => {
    pending = callback
    return 1
  }
  globalThis.cancelAnimationFrame = () => {
    pending = null
  }
  t.after(() => {
    globalThis.requestAnimationFrame = original.raf
    globalThis.cancelAnimationFrame = original.caf
  })
  return {
    runFrames(count, startAt = 1000) {
      for (let i = 0; i < count && pending; i++) {
        const callback = pending
        pending = null
        callback(startAt + i * FRAME_MS)
      }
    },
  }
}

const sixKilometreTrack = {
  type: "Feature",
  geometry: {
    type: "LineString",
    coordinates: [
      [12.3, LATITUDE],
      [12.386, LATITUDE],
    ],
  },
  properties: { id: 1, color: "#6366F1" },
}

function phaseOf(gradient, numDashes) {
  const period = 1 / numDashes
  const stops = []
  for (let i = 3; i < gradient.length; i += 2)
    stops.push([gradient[i], gradient[i + 1]])
  for (let i = 0; i < stops.length - 1; i++) {
    const [start, startColor] = stops[i]
    const [end, endColor] = stops[i + 1]
    if (
      startColor === HIGHLIGHT &&
      endColor === HIGHLIGHT &&
      Math.abs(end - start - 0.15 * period) < 1e-6
    ) {
      const center = (start + end) / 2
      return (((center / period) % 1) + 1) % 1
    }
  }
  throw new Error("no full dash in gradient")
}

function screenSpeed(t, zoom) {
  const frames = installFrameDriver(t)
  const map = fakeMap(zoom)
  const tracksLayer = new TracksLayer(map)
  tracksLayer.add({ type: "FeatureCollection", features: [] })
  tracksLayer.setSelectedTrack(sixKilometreTrack)
  frames.runFrames(61)

  const numDashes = Math.max(
    4,
    Math.min(30, Math.round(tracksLayer.selectedTrackLength / 400)),
  )
  const phases = map.gradients.map((gradient) => phaseOf(gradient, numDashes))
  const travelled = phases
    .slice(1)
    .reduce((sum, phase, i) => sum + ((((phase - phases[i]) % 1) + 1) % 1), 0)
  const elapsedSeconds = 60 * (FRAME_MS / 1000)
  const phasePerSecond = travelled / elapsedSeconds
  const metersPerPixel =
    (40075016.686 * Math.cos((LATITUDE * Math.PI) / 180)) / (512 * 2 ** zoom)
  const periodPixels =
    tracksLayer.selectedTrackLength / numDashes / metersPerPixel
  return {
    pixelsPerSecond: phasePerSecond * periodPixels,
    paints: map.gradients.length,
  }
}

test("the selected-track flow moves at a calm screen speed when zoomed in", (t) => {
  const { pixelsPerSecond } = screenSpeed(t, 15)

  assert.ok(
    pixelsPerSecond > 30 && pixelsPerSecond < 50,
    `got ${pixelsPerSecond.toFixed(1)} px/s`,
  )
})

test("the flow keeps the same screen speed at a lower zoom", (t) => {
  const { pixelsPerSecond } = screenSpeed(t, 12)

  assert.ok(
    pixelsPerSecond > 30 && pixelsPerSecond < 50,
    `got ${pixelsPerSecond.toFixed(1)} px/s`,
  )
})

test("the flow gradient is rebuilt at most about 30 times per second", (t) => {
  const { paints } = screenSpeed(t, 15)

  assert.ok(paints <= 32, `got ${paints} gradient rebuilds in one second`)
})
