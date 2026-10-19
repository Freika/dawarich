import assert from "node:assert/strict"
import { test } from "node:test"
import { createReader } from "../../app-phoenix/assets/js/map/data/reader.js"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("map host timeline hover reads the canonical track and clears on range replacement", async () => {
  const f = fixture()
  try {
    await f.owner.mount()
    f.root.emit("pointerover", {
      target: { closest: () => ({ dataset: { trackId: "7" } }) },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(
      f.reads.find(({ resource }) => resource === "track"),
      { resource: "track", params: { id: "7" } },
    )
    assert.equal(
      f.sources.get("native-timeline-hover").data.geometry.coordinates.length,
      2,
    )
    await f.owner.update({ ...f.owner.config, revision: 2 })
    assert.equal(f.sources.has("native-timeline-hover"), false)
    f.owner.destroy()
    assert.equal(f.root.listeners.get("pointerover").size, 0)
  } finally {
    f.owner.destroy()
  }
})

test("native host track selection fits canonical geometry shows owned points and clears on close", async () => {
  const f = fixture()
  const fits = []
  f.map.fitBounds = (...args) => fits.push(args)
  f.reader.pages = async (resource, params) => {
    f.reads.push({ resource, params })
    return [{ id: 9, longitude: "12", latitude: "51" }]
  }
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 7, points: false })
    assert.equal(f.sources.has("native-selected-track"), true)
    assert.equal(f.layers.has("track-points"), false)
    assert.deepEqual(fits[0][0], [
      [12, 51],
      [14, 53],
    ])
    await f.owner.timeline.select({ id: 7, points: true })
    assert.equal(
      f.sources.get("track-points-source").data.features[0].properties.id,
      9,
    )
    assert.equal(f.layers.has("track-points"), true)
    await f.owner.timeline.select({ id: null, points: false })
    assert.equal(f.sources.has("native-selected-track"), false)
    assert.equal(f.sources.has("track-points-source"), false)
  } finally {
    f.owner.destroy()
  }
})
test("native track selection ignores late geometry after replacement and disposal", async () => {
  const f = fixture()
  let finish
  f.reader.read = () =>
    new Promise((resolve) => {
      finish = resolve
    })
  try {
    await f.owner.mount()
    const selection = f.owner.timeline.select({ id: 7, points: true })
    await Promise.resolve()
    f.owner.destroy()
    finish({
      data: {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: [
            [12, 51],
            [14, 53],
          ],
        },
        properties: {},
      },
    })
    await selection
    assert.equal(f.sources.has("native-selected-track"), false)
    assert.equal(f.layers.has("track-points"), false)
    assert.equal(f.root.listeners.get("click").size, 0)
  } finally {
    f.owner.destroy()
  }
})
test("native track clicks send only owned scalar commands and replay seeks the source profile day", async () => {
  const f = fixture({ tracksEnabled: true })
  const replay = []
  try {
    await f.owner.mount()
    f.map.queryRenderedFeatures = (_point, { layers }) =>
      layers.includes("points-mvt")
        ? []
        : [{ properties: { id: 7 }, layer: { id: "tracks-mvt" } }]
    f.map.emit("click", { point: { x: 20, y: 20 } })
    assert.ok(
      f.pushed.some(
        ({ event, payload }) =>
          event === "map:select" &&
          payload.kind === "track" &&
          payload.id === 7,
      ),
    )
    f.owner.replay = {
      close() {},
      active: false,
      open: async () => "ready",
      playing: false,
      manager: {
        hasData: () => true,
        goToDay: (day) => replay.push(day),
        minuteOfDay: () => 660,
      },
      seek: (minute) => replay.push(minute),
      play: () => replay.push("play"),
    }
    f.root.emit("click", {
      target: {
        closest: (selector) =>
          selector === "[data-native-track-replay]"
            ? {
                dataset: { trackStart: "2026-03-30T11:00:00+02:00" },
              }
            : null,
      },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(replay, ["2026-03-30", 660, "play"])
    f.owner.replay.active = true
    f.root.emit("click", {
      target: {
        closest: (selector) =>
          selector === "[data-native-track-replay]"
            ? {
                dataset: { trackStart: "2026-03-30T11:00:00+02:00" },
              }
            : null,
      },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(replay, ["2026-03-30", 660, "play", "play"])
    f.map.queryRenderedFeatures = () => []
    f.map.emit("click", { point: { x: 30, y: 30 } })
    assert.ok(f.pushed.some(({ event }) => event === "track:close"))
  } finally {
    f.owner.destroy()
  }
})

test("map track hover mirrors the native journey row and removes its owned hover drawing", async () => {
  const f = fixture({ tracksEnabled: true })
  const row = new Element()
  const classes = { has: (value) => row.classList.contains(value) }
  const canvas = { style: { cursor: "" } }
  f.map.getCanvas = () => canvas
  f.nodes.set('[data-track-id="7"]', row)
  f.map.queryRenderedFeatures = (_point, { layers }) =>
    layers.includes("points-mvt")
      ? []
      : [{ properties: { id: 7 }, layer: { id: "tracks-mvt" } }]
  try {
    await f.owner.mount()
    f.map.emit("mousemove", { point: { x: 20, y: 30 } })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(row["data-track-hovered"], "true")
    assert.equal(classes.has("bg-base-200"), true)
    assert.equal(canvas.style.cursor, "pointer")
    assert.equal(f.sources.has("native-timeline-hover"), true)
    f.map.emit("mouseleave")
    assert.equal(row["data-track-hovered"], "false")
    assert.equal(classes.has("bg-base-200"), false)
    assert.equal(canvas.style.cursor, "")
    assert.equal(f.sources.has("native-timeline-hover"), false)
  } finally {
    f.owner.destroy()
  }
})

test("native selected segments retain parent identity color and source endpoint markers until disposal", async () => {
  const markers = [],
    removed = []
  class Marker {
    constructor({ element }) {
      this.element = element
      markers.push(this)
    }
    setLngLat(coordinates) {
      this.coordinates = coordinates
      return this
    }
    addTo() {
      return this
    }
    remove() {
      removed.push(this)
    }
  }
  const f = fixture({}, { library: { Marker } })
  f.reader.read = async () => ({
    data: {
      type: "Feature",
      geometry: {
        type: "LineString",
        coordinates: [
          [12, 51],
          [14, 53],
        ],
      },
      properties: {
        id: 7,
        dominant_mode_emoji: "🚲",
        segments: [
          {
            id: 19,
            emoji: "🚶",
            color: "#3B82F6",
            coordinates: [
              [12, 51],
              [14, 53],
            ],
            mode: "cycling",
          },
          {
            id: 20,
            emoji: "🚲",
            color: "#22C55E",
            coordinates: [
              [13, 52],
              [14, 53],
            ],
            mode: "cycling",
          },
        ],
      },
    },
  })
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 7 })
    const segment = f.sources.get("native-selected-track").data.features[1]
    assert.equal(segment.properties.track_id, 7)
    assert.equal(segment.properties.color, "#3B82F6")
    assert.deepEqual(
      markers.map((marker) => marker.element.textContent),
      ["🚶", "🚲", "🏁"],
    )
    f.owner.destroy()
    assert.equal(removed.length, 3)
    assert.equal(f.sources.has("native-selected-track"), false)
  } finally {
    f.owner.destroy()
  }
})

test("native segment row and map hover use the owned exact segment geometry and clear the previous row", async () => {
  const f = fixture({ tracksEnabled: true })
  const rows = [new Element(), new Element()]
  f.nodes.set('[data-segment-id="19"]', rows[0])
  f.nodes.set('[data-segment-id="20"]', rows[1])
  const track = {
    type: "Feature",
    geometry: {
      type: "LineString",
      coordinates: [
        [12, 51],
        [13, 52],
        [14, 53],
      ],
    },
    properties: {
      id: 7,
      segments: [
        {
          id: 19,
          coordinates: [
            [12, 51],
            [13, 52],
          ],
          start_index: 0,
          end_index: 1,
        },
        {
          id: 20,
          coordinates: [
            [13, 52],
            [14, 53],
          ],
          start_index: 1,
          end_index: 2,
        },
      ],
    },
  }
  f.reader.read = async () => ({ data: track })
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 7 })
    f.root.emit("pointerover", {
      target: {
        closest: () => ({ dataset: { trackId: "7", segmentId: "19" } }),
      },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(
      f.sources.get("native-timeline-hover").data.geometry.coordinates,
      [
        [12, 51],
        [13, 52],
      ],
    )
    f.map.queryRenderedFeatures = () => [
      {
        layer: { id: "native-selected-track-segments" },
        properties: { id: 19, track_id: 7 },
      },
    ]
    f.map.emit("mousemove", { point: { x: 20, y: 20 } })
    assert.equal(rows[0]["data-track-hovered"], "true")
    f.map.queryRenderedFeatures = () => [
      {
        layer: { id: "native-selected-track-segments" },
        properties: { id: 20, track_id: 7 },
      },
    ]
    f.map.emit("mousemove", { point: { x: 30, y: 30 } })
    assert.equal(rows[0]["data-track-hovered"], "false")
    assert.equal(rows[1]["data-track-hovered"], "true")
    assert.deepEqual(
      f.sources.get("native-timeline-hover").data.geometry.coordinates,
      [
        [13, 52],
        [14, 53],
      ],
    )
    f.map.emit("mouseleave")
    assert.equal(f.sources.has("native-timeline-hover"), false)
    assert.equal(rows[1]["data-track-hovered"], "false")
    const enter = () =>
      f.root.emit("pointerover", {
        target: {
          closest: () => ({ dataset: { trackId: "7", segmentId: "19" } }),
        },
      })
    track.properties.segments[0].coordinates = undefined
    enter()
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(
      f.sources.get("native-timeline-hover").data.geometry.coordinates,
      [
        [12, 51],
        [13, 52],
      ],
    )
    for (const change of [
      { start_index: -1 },
      {
        start_index: 0,
        coordinates: [
          [-181, 51],
          [13, 52],
        ],
      },
      {
        coordinates: [
          [12, 51],
          [NaN, 52],
        ],
      },
    ]) {
      f.root.emit("pointerout")
      Object.assign(track.properties.segments[0], change)
      enter()
      await new Promise((resolve) => setImmediate(resolve))
      assert.equal(f.sources.has("native-timeline-hover"), false)
    }
    Object.assign(track.properties.segments[0], {
      start_index: 0,
      coordinates: [
        [12, 51],
        [13, 52],
      ],
    })
    f.root.emit("pointerout")
    f.root.emit("pointerover", {
      target: {
        closest: () => ({ dataset: { trackId: "7", segmentId: "foreign" } }),
      },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(f.sources.has("native-timeline-hover"), false)
  } finally {
    f.owner.destroy()
  }
})

test("native canonical track owner consumes the real cookie FeatureCollection shape", async () => {
  const f = fixture()
  const feature = {
    type: "Feature",
    geometry: {
      type: "LineString",
      coordinates: [
        [12, 51],
        [14, 53],
      ],
    },
    properties: { id: 7, segments: [] },
  }
  const actual = createReader({
    origin: "https://map.test",
    fetch: async (url) =>
      new Response(
        JSON.stringify(
          url.endsWith("/7")
            ? { type: "FeatureCollection", features: [feature] }
            : [{ id: 9, longitude: "12", latitude: "51" }],
        ),
        { headers: { "x-total-pages": "1" } },
      ),
  })
  const read = f.reader.read
  f.reader.read = (resource, ...args) =>
    resource === "track"
      ? actual.read(resource, ...args)
      : read(resource, ...args)
  f.reader.pages = (...args) => actual.pages(...args)
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 7, points: true })
    assert.equal(f.sources.has("native-selected-track"), true)
    assert.deepEqual(
      f.sources.get("native-selected-track").data.features[0].geometry,
      feature.geometry,
    )
    assert.equal(
      f.sources.get("track-points-source").data.features[0].properties.id,
      9,
    )
  } finally {
    f.owner.destroy()
    actual.destroy()
  }
})

test("native timeline keyboard steps profile calendar dates ignores text inputs and releases its listener", async () => {
  const f = fixture({ panel: "timeline" })
  const document = new Element()
  f.root.ownerDocument = document
  f.root.dataset.nativeSelectedDate = "2026-03-29"
  const key = (name, target = { closest: () => null }) => ({
    key: name,
    target,
    preventDefault() {},
  })
  try {
    await f.owner.mount()
    document.emit("keydown", key("ArrowLeft"))
    assert.deepEqual(
      f.pushed.filter(({ event }) => event === "calendar:day").at(-1).payload,
      { date: "2026-03-28" },
    )
    f.root.dataset.nativeSelectedDate = "2026-03-30"
    document.emit("keydown", key("ArrowRight"))
    assert.deepEqual(
      f.pushed.filter(({ event }) => event === "calendar:day").at(-1).payload,
      { date: "2026-03-31" },
    )
    document.emit("keydown", key("ArrowRight", { closest: () => ({}) }))
    f.owner.config.panel = "layers"
    document.emit("keydown", key("ArrowRight"))
    assert.equal(
      f.pushed.filter(({ event }) => event === "calendar:day").length,
      2,
    )
    f.owner.destroy()
    assert.equal(document.listeners.get("keydown").size, 0)
    document.emit("keydown", key("ArrowRight"))
    assert.equal(
      f.pushed.filter(({ event }) => event === "calendar:day").length,
      2,
    )
  } finally {
    f.owner.destroy()
  }
})

test("empty native tool status whitespace permits track clicks and hover while armed tools block them", async () => {
  const f = fixture({ tracksEnabled: true })
  const status = new Element()
  const canvas = { style: {} }
  f.map.getCanvas = () => canvas
  status.textContent = "\n        "
  f.nodes.set("[data-map-tool-status]", status)
  f.map.queryRenderedFeatures = (_point, { layers }) =>
    layers.includes("points-mvt")
      ? []
      : [{ properties: { id: 7 }, layer: { id: "tracks-mvt" } }]
  try {
    await f.owner.mount()
    f.map.emit("click", { point: { x: 20, y: 20 } })
    assert.ok(
      f.pushed.some(
        ({ event, payload }) =>
          event === "map:select" &&
          payload.kind === "track" &&
          payload.id === 7,
      ),
    )
    f.map.emit("mousemove", { point: { x: 20, y: 20 } })
    assert.equal(f.map.getCanvas().style.cursor, "pointer")
    const count = f.pushed.filter(({ event }) => event === "map:select").length
    status.textContent = "Click to place a visit"
    f.map.emit("click", { point: { x: 20, y: 20 } })
    assert.equal(
      f.pushed.filter(({ event }) => event === "map:select").length,
      count,
    )
  } finally {
    f.owner.destroy()
  }
})

test("selected index-based segments render the canonical track slice for map hover", async () => {
  const f = fixture()
  const coordinates = [
    [12, 51],
    [13, 52],
    [14, 53],
  ]
  f.reader.read = async () => ({
    data: {
      type: "Feature",
      geometry: { type: "LineString", coordinates },
      properties: {
        id: 7,
        segments: [{ id: 19, start_index: 1, end_index: 2, color: "#3B82F6" }],
      },
    },
  })
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 7 })
    const rendered = f.sources.get("native-selected-track").data.features[1]
    assert.deepEqual(rendered.geometry, {
      type: "LineString",
      coordinates: coordinates.slice(1, 3),
    })
    assert.equal(rendered.properties.track_id, 7)
    assert.equal(rendered.properties.color, "#3B82F6")
    f.root.emit("pointerover", {
      target: {
        closest: () => ({ dataset: { trackId: "7", segmentId: "19" } }),
      },
    })
    assert.deepEqual(
      f.sources.get("native-timeline-hover").data.geometry,
      rendered.geometry,
    )
  } finally {
    f.owner.destroy()
  }
})

test("native map track hits ignore blank tool markup but refuse armed placement", async () => {
  const f = fixture({ tracksEnabled: true })
  const status = new Element()
  status.textContent = "\n  "
  f.nodes.set("[data-map-tool-status]", status)
  f.map.queryRenderedFeatures = (_point, { layers }) =>
    layers.includes("points-mvt")
      ? []
      : [{ properties: { id: 7 }, layer: { id: "tracks-mvt" } }]
  try {
    await f.owner.mount()
    f.map.emit("click", { point: { x: 20, y: 20 } })
    assert.equal(
      f.pushed.filter(({ event }) => event === "map:select").length,
      1,
    )
    status.textContent = "Click to place the visit"
    f.map.emit("click", { point: { x: 20, y: 20 } })
    assert.equal(
      f.pushed.filter(({ event }) => event === "map:select").length,
      1,
    )
  } finally {
    f.owner.destroy()
  }
})
