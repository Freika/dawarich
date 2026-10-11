import assert from "node:assert/strict"
import { test } from "node:test"
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
    f.map.queryRenderedFeatures = () => [
      { properties: { id: 7 }, layer: { id: "tracks-mvt" } },
    ]
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
        closest: () => ({
          dataset: { trackStart: "2026-03-30T11:00:00+02:00" },
        }),
      },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(replay, ["2026-03-30", 660, "play"])
    f.owner.replay.active = true
    f.root.emit("click", {
      target: {
        closest: () => ({
          dataset: { trackStart: "2026-03-30T11:00:00+02:00" },
        }),
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
  const classes = new Set()
  row.classList = {
    add: (value) => classes.add(value),
    remove: (value) => classes.delete(value),
  }
  const canvas = { style: { cursor: "" } }
  f.map.getCanvas = () => canvas
  f.nodes.set('[data-track-id="7"]', row)
  f.map.queryRenderedFeatures = () => [
    { properties: { id: 7 }, layer: { id: "tracks-mvt" } },
  ]
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
            color: "#3B82F6",
            coordinates: [
              [12, 51],
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
      ["🚲", "🏁"],
    )
    f.owner.destroy()
    assert.equal(removed.length, 2)
    assert.equal(f.sources.has("native-selected-track"), false)
  } finally {
    f.owner.destroy()
  }
})
