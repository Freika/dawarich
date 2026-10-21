import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import { test } from "node:test"
import {
  createPreviewGate,
  mountPreview,
} from "../../app-phoenix/assets/js/map/preview/runtime.js"
import { createPublicStatsReader } from "../../app-phoenix/assets/js/map/public/stats_reader.js"

const turn = () => new Promise((r) => setImmediate(r))
function fixture(gate = createPreviewGate(2)) {
  let visible,
    constructed = 0,
    removed = 0,
    refreshed = 0
  const element = {
    dataset: { mapConfig: JSON.stringify({ tripId: 4 }) },
    ownerDocument: {},
  }
  const owner = mountPreview({
    element,
    gate,
    observe: (_, callback) => {
      visible = callback
      return () => {
        visible = null
      }
    },
    createOwner: () => {
      constructed++
      return {
        mount: async () => "ready",
        destroy: () => {
          removed++
        },
        update: async () => {
          refreshed++
        },
      }
    },
  })
  return {
    owner,
    show: (v) => visible?.(v),
    get constructed() {
      return constructed
    },
    get removed() {
      return removed
    },
    get refreshed() {
      return refreshed
    },
  }
}
test("hidden preview does not allocate a map and leaving destroys all initialized previews", async () => {
  const f = fixture()
  f.owner.mount()
  await turn()
  assert.equal(f.constructed, 0)
  f.show(true)
  await turn()
  assert.equal(f.constructed, 1)
  f.show(false)
  await turn()
  assert.equal(f.removed, 1)
  f.show(true)
  await turn()
  assert.equal(f.constructed, 2)
  f.owner.destroy()
  assert.equal(f.removed, 2)
  f.show(true)
  await turn()
  assert.equal(f.constructed, 2)
})
test("preview queue caps live owners and drops destroyed queued previews", async () => {
  const gate = createPreviewGate(1),
    a = fixture(gate),
    b = fixture(gate),
    c = fixture(gate)
  for (const f of [a, b, c]) {
    f.owner.mount()
    f.show(true)
  }
  await turn()
  assert.equal(a.constructed, 1)
  assert.equal(b.constructed, 0)
  assert.equal(c.constructed, 0)
  b.owner.destroy()
  a.owner.destroy()
  await turn()
  assert.equal(b.constructed, 0)
  assert.equal(c.constructed, 1)
  c.owner.destroy()
  assert.equal(gate.active, 0)
})
test("preview configuration patches reuse a visible owner and preserve readonly settings", async () => {
  const f = fixture()
  f.owner.mount()
  f.show(true)
  await turn()
  await f.owner.update({ tripId: 5, revision: 2 })
  assert.equal(f.constructed, 1)
  assert.equal(f.refreshed, 1)
  f.owner.destroy()
})
test("public stats preview never requests private geometry or account credentials", async () => {
  const calls = []
  const reader = createPublicStatsReader({
    origin: "https://maps.example",
    fetch: async (url, options) => {
      calls.push({ url, options })
      return { ok: true, json: async () => ({ features: [] }) }
    },
  })
  const result = await reader.read("hexagons", {
    uuid: "public-share",
    start_date: "1900-01-01",
    api_key: "synthetic-secret",
  })
  assert.deepEqual(result.data, { features: [] })
  const url = new URL(calls[0].url)
  assert.equal(url.pathname, "/api/v1/maps/hexagons")
  assert.deepEqual([...url.searchParams], [["uuid", "public-share"]])
  assert.equal(calls[0].options.credentials, "omit")
  assert.equal(calls[0].options.headers.Authorization, undefined)
  await assert.rejects(
    reader.read("points", { uuid: "public-share" }),
    /Unsupported/,
  )
  reader.destroy()
})
test("public stats destruction aborts a noncooperative geometry response", async () => {
  let complete, signal
  const reader = createPublicStatsReader({
    origin: "https://maps.example",
    fetch: async (_, options) => {
      signal = options.signal
      return new Promise((r) => {
        complete = r
      })
    },
  })
  const reading = reader.read("hexagons", { uuid: "share" })
  await turn()
  reader.destroy()
  complete({ ok: true, json: async () => ({ features: [{ id: 1 }] }) })
  await assert.rejects(reading, (e) => e.name === "AbortError")
  assert.equal(signal.aborted, true)
})

test("preview route uses owned HTTP geometry across dateline and clears stale empty path", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map(),
    reads = []
  let removed = 0,
    mapOptions,
    path = [
      [179, 10],
      [-179, 11],
    ]
  const element = {
    dataset: {},
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  class MapLibre {
    constructor(options) {
      mapOptions = options
    }
    loaded() {
      return true
    }
    on(name, f) {
      listeners.set(name, f)
    }
    once(name, f) {
      listeners.set(name, f)
    }
    off(name) {
      listeners.delete(name)
    }
    addSource(id, s) {
      sources.set(id, s)
    }
    addLayer(l) {
      layers.set(l.id, l)
    }
    getSource(id) {
      return sources.get(id)
    }
    getLayer(id) {
      return layers.get(id)
    }
    removeSource(id) {
      sources.delete(id)
    }
    removeLayer(id) {
      layers.delete(id)
    }
    fitBounds() {}
    remove() {
      removed++
    }
  }
  const library = {
    Map: MapLibre,
    LngLatBounds: class {
      extend() {}
      isEmpty() {
        return false
      }
    },
  }
  const reader = {
    read: async (resource, params) => {
      reads.push({ resource, params })
      return { data: { path, plan: null } }
    },
    reset() {},
    destroy() {},
  }
  const owner = createPreviewOwner({
    element,
    config: { tripId: 7, interactive: false },
    reader,
    loadLibrary: async () => library,
    loadStyle: async () => ({}),
  })
  assert.equal(await owner.mount(), "ready")
  assert.deepEqual(reads, [{ resource: "trip", params: { id: 7 } }])
  assert.equal(mapOptions.interactive, false)
  assert.equal(
    sources.get("preview-route").data.geometry.type,
    "MultiLineString",
  )
  assert.equal(sources.get("preview-route").data.geometry.coordinates.length, 2)
  path = []
  await owner.update({ tripId: 7, revision: 2 })
  assert.equal(sources.has("preview-route"), false)
  owner.destroy()
  assert.equal(layers.size, 0)
  assert.equal(sources.size, 0)
  assert.equal(listeners.size, 0)
  assert.equal(removed, 1)
})

test("public preview refusal clears previously displayed geometry before retry", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map()
  let refused = false
  const element = {
    dataset: {},
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  const map = {
    loaded: () => true,
    on: (name, f) => listeners.set(name, f),
    once() {},
    off: (name) => listeners.delete(name),
    addSource: (id, s) => sources.set(id, s),
    addLayer: (l) => layers.set(l.id, l),
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    removeSource: (id) => sources.delete(id),
    removeLayer: (id) => layers.delete(id),
    fitBounds() {},
    remove() {},
    getCanvas: () => ({ style: {} }),
    setFeatureState() {},
  }
  const reader = {
    read: async () => {
      if (refused) throw new Error("revoked")
      return { data: { features: [{ id: 7 }] } }
    },
    reset() {},
    destroy() {},
  }
  const owner = createPreviewOwner({
    element,
    config: { kind: "stats", uuid: "share" },
    reader,
    loadLibrary: async () => ({
      Map: class {
        constructor() {
          Object.assign(this, map)
        }
      },
    }),
    loadStyle: async () => ({}),
  })
  assert.equal(await owner.mount(), "ready")
  assert.equal(sources.has("hexagons"), true)
  refused = true
  assert.equal(await owner.reconnect(), "failed")
  assert.equal(sources.has("hexagons"), false)
  assert.equal(element.dataset.mapState, "failed")
  refused = false
  assert.equal(await owner.reconnect(), "ready")
  owner.destroy()
})

test("preview reconnect refreshes admission on its existing visible owner", async () => {
  let change,
    refreshed = 0,
    constructed = 0
  const element = { dataset: { mapConfig: "{}" }, ownerDocument: {} }
  const owner = mountPreview({
    element,
    gate: createPreviewGate(),
    observe: (_, f) => {
      change = f
      return () => {}
    },
    createOwner: () => {
      constructed++
      return {
        mount: async () => {},
        reconnect: async () => {
          refreshed++
        },
        destroy() {},
      }
    },
  })
  owner.mount()
  change(true)
  await turn()
  await owner.reconnect()
  assert.equal(refreshed, 1)
  assert.equal(constructed, 1)
  owner.destroy()
})

test("new Trip empty preview settles without history or invalid range request", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const element = {
    dataset: {},
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
    appendChild() {},
  }
  const map = {
    loaded: () => true,
    on() {},
    off() {},
    getSource() {},
    getLayer() {},
    remove() {},
  }
  const owner = createPreviewOwner({
    element,
    config: { interactive: true },
    reader: {
      read() {
        throw new Error("unexpected read")
      },
      pages() {
        throw new Error("unexpected history")
      },
      destroy() {},
      reset() {},
    },
    loadLibrary: async () => ({
      Map: class {
        constructor() {
          Object.assign(this, map)
        }
      },
    }),
    loadStyle: async () => ({}),
  })
  assert.equal(await owner.mount(), "ready")
  owner.destroy()
})

test("readonly trip previews preserve every saved style and omit navigation controls", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const previous = globalThis.fetch
  const urls = []
  globalThis.fetch = async (url) => {
    urls.push(url)
    return {
      ok: true,
      json: async () => ({ version: 8, sources: {}, layers: [] }),
    }
  }
  try {
    for (const styleName of ["white", "black", "grayscale", "dark", "light"]) {
      let controls = 0
      const owner = createPreviewOwner({
        element: {
          dataset: {},
          ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
          appendChild() {},
        },
        config: { styleName, interactive: false },
        reader: { reset() {}, destroy() {} },
        loadLibrary: async () => ({
          NavigationControl: class {},
          Map: class {
            loaded() {
              return true
            }
            on() {}
            off() {}
            addControl() {
              controls++
            }
            getSource() {}
            getLayer() {}
            remove() {}
          },
        }),
      })
      try {
        assert.equal(await owner.mount(), "ready")
        assert.equal(urls.at(-1), `/maps_maplibre/styles/${styleName}.json`)
        assert.equal(controls, 0)
      } finally {
        owner.destroy()
      }
    }
  } finally {
    globalThis.fetch = previous
  }
})

test("owned monthly preview matches Rails point heatmap and reader theme controls", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map()
  const reads = [],
    controls = [],
    styles = [],
    fits = []
  let mapOptions
  const element = {
    dataset: {},
    ownerDocument: {
      documentElement: { dataset: { theme: "dawarich-dark" } },
      createElement: () => ({ style: {}, remove() {} }),
    },
    appendChild() {},
  }
  const map = {
    loaded: () => true,
    on: (name, f) => listeners.set(name, f),
    once() {},
    off: (name) => listeners.delete(name),
    addSource: (id, s) => sources.set(id, s),
    addLayer: (l) => layers.set(l.id, l),
    getSource: (id) => sources.get(id),
    getLayer: (id) => layers.get(id),
    removeSource: (id) => sources.delete(id),
    removeLayer: (id) => layers.delete(id),
    fitBounds(bounds, options) {
      fits.push({ bounds, options })
    },
    addControl(control, position) {
      controls.push({ control, position })
    },
    remove() {},
    getCanvas: () => ({ style: {} }),
    setFeatureState() {},
  }
  const reader = {
    read: async (resource, params) => {
      reads.push([resource, params])
      return { data: { features: [{ id: 7 }] } }
    },
    pages: async (resource, params) => {
      reads.push([resource, params])
      return [
        { latitude: 52, longitude: 13, timestamp: 1 },
        { latitude: 0, longitude: 13 },
        { latitude: "invalid", longitude: 14 },
      ]
    },
    reset() {},
    destroy() {},
  }
  const owner = createPreviewOwner({
    element,
    config: {
      kind: "owned_stats",
      layer: "heatmap",
      range: {
        startAt: "2025-04-01T00:00:00Z",
        endAt: "2025-04-30T23:59:59Z",
        timezone: "UTC",
      },
    },
    reader,
    loadLibrary: async () => ({
      NavigationControl: class {
        constructor(options) {
          this.kind = "navigation"
          this.options = options
        }
      },
      AttributionControl: class {
        constructor(options) {
          this.kind = "attribution"
          this.options = options
        }
      },
      ScaleControl: class {
        constructor(options) {
          this.kind = "scale"
          this.options = options
        }
      },
      Map: class {
        constructor(options) {
          mapOptions = options
          Object.assign(this, map)
        }
      },
    }),
    loadStyle: async (config) => {
      styles.push(config)
      return {}
    },
  })
  assert.equal(await owner.mount(), "ready")
  const source = readFileSync(
    new URL(
      "../../app/javascript/controllers/stat_page_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
  const paint = JSON.parse(
    JSON.stringify(
      runInNewContext(
        "(" + source.match(/const HEATMAP_PAINT = (\{[\s\S]*?\n\})/)[1] + ")",
      ),
    ),
  )
  assert.equal(layers.get("stat-heatmap").type, "heatmap")
  assert.deepEqual(layers.get("stat-heatmap").paint, paint)
  assert.deepEqual(
    sources.get("stat-points").data.features.map((f) => f.geometry.coordinates),
    [[13, 52]],
  )
  assert.equal(reads[0][0], "points")
  assert.equal(reads[0][1].start_at, "2025-04-01T00:00:00Z")
  assert.equal(styles[0].styleName, "dark")
  assert.deepEqual(
    controls.map(({ control, position }) => [
      control.kind,
      control.options,
      position,
    ]),
    [
      ["navigation", { showCompass: false }, "top-right"],
      ["attribution", { compact: true }, undefined],
      ["scale", { maxWidth: 100 }, "bottom-right"],
    ],
  )
  assert.equal(mapOptions.attributionControl, false)
  assert.deepEqual(fits[0].options, { padding: 40, maxZoom: 14, duration: 0 })
  assert.equal(
    await owner.update({
      kind: "owned_stats",
      layer: "points",
      range: { startAt: "2025-04-01T00:00:00Z", endAt: "2025-04-30T23:59:59Z" },
    }),
    "ready",
  )
  assert.equal(reads.at(-1)[0], "points")
  assert.equal(
    reads.some(
      ([resource]) => resource === "hexagons" || resource === "bounds",
    ),
    false,
  )
  assert.equal(layers.get("stat-circles").layout.visibility, "visible")
  assert.equal(layers.get("stat-heatmap").layout.visibility, "none")
  assert.equal(layers.get("stat-circles").paint["circle-color"], "#570df8")
  await owner.update({
    kind: "owned_stats",
    layer: "none",
    range: { startAt: "2025-04-01T00:00:00Z", endAt: "2025-04-30T23:59:59Z" },
  })
  assert.equal(layers.get("stat-circles").layout.visibility, "none")
  assert.equal(layers.get("stat-heatmap").layout.visibility, "none")
  owner.destroy()
})

test("dark trip form previews paint the saved light palette instead of the reader theme", async () => {
  const { createPreviewOwner } = await import(
    "../../app-phoenix/assets/js/map/preview/owner.js"
  )
  const { readFile } = await import("node:fs/promises")
  const { fetchStyle } = await import(
    "../../app-phoenix/assets/js/map/style/load_style.js"
  )
  const styles = []
  for (const tripId of [undefined, 7]) {
    const owner = createPreviewOwner({
      element: {
        dataset: {},
        ownerDocument: {
          documentElement: { dataset: { theme: "dawarich-dark" } },
          createElement: () => ({ style: {}, remove() {} }),
        },
        appendChild() {},
      },
      config: { interactive: true, styleName: "light", tripId },
      reader: {
        read: async () => ({ data: { path: [] } }),
        reset() {},
        destroy() {},
      },
      loadStyle: (config, options) =>
        fetchStyle(config, {
          ...options,
          fetch: async (url) => ({
            ok: true,
            json: async () => JSON.parse(await readFile(
              new URL(`../../public${url}`, import.meta.url), "utf8",
            )),
          }),
        }),
      loadLibrary: async () => ({
        Map: class {
          constructor(options) {
            styles.push(options.style)
          }
          loaded() {
            return true
          }
          on() {}
          off() {}
          getSource() {}
          getLayer() {}
          remove() {}
        },
      }),
    })
    try {
      assert.equal(await owner.mount(), "ready")
      assert.equal(owner.config.styleName, "light")
      const palette = styles.at(-1)
      const background = palette.layers.find(layer => layer.id === "background")
      assert.equal(
        background.paint["background-color"],
        "#cccccc",
      )
      assert.equal(
        palette.layers.find(layer => layer.id === "earth").paint["fill-color"],
        "#e2dfda",
      )
      assert.equal(palette.sources.protomaps.url, undefined)
      assert.match(
        palette.sources.protomaps.tiles[0],
        /\/planet\/\{z\}\/\{x\}\/\{y\}\.mvt$/,
      )
    } finally {
      owner.destroy()
    }
  }
})
