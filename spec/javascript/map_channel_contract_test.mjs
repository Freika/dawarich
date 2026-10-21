import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/channels/map_channel.js",
    import.meta.url,
  ),
  "utf8",
)
const boundary = `
export const created = []
export let consumer = { subscriptions: { create(name, callbacks) {
  const subscription = { name, callbacks, unsubscribes: 0, unsubscribe() { this.unsubscribes++ } }
  created.push(subscription)
  return subscription
} } }
export function withoutConsumer() { consumer = null }
`
const { createMapChannel, created, withoutConsumer } = await import(
  `data:text/javascript;base64,${Buffer.from(source.replace('import consumer from "../../channels/consumer"', boundary)).toString("base64")}`
)

const pointOracle = {
  source: "app/models/point.rb#broadcast_coordinates",
  spec: "spec/models/point_spec.rb",
  example: "broadcasts the complete live point tuple with a nonempty country",
  payload: [52.52, 13.405, "85", "100.0", "1700000000", "5", "405", "Germany"],
}
const upsertOracle = {
  source: "app/services/points/live_broadcaster.rb#broadcast_points",
  spec: "spec/services/points/live_broadcaster_spec.rb",
  example: "broadcasts point data to PointsChannel",
  payload: [52.52, 13.405, "85", "100", "1700000000", "5.0", "1", ""],
}
const familyOracles = [
  {
    source: "app/models/point.rb#broadcast_to_family",
    spec: "spec/models/point_spec.rb",
    example: "broadcasts the complete family member with timezone updated_at",
    payload: {
      user_id: 1,
      email: "a6-point@example.test",
      email_initial: "A",
      latitude: 52.52,
      longitude: 13.405,
      timestamp: 1700000000,
      updated_at: "2023-11-14T23:13:20+01:00",
    },
  },
  {
    source: "app/services/points/live_broadcaster.rb#broadcast_family",
    spec: "spec/services/points/live_broadcaster_spec.rb",
    example: "broadcasts to FamilyLocationsChannel with the user payload",
    payload: {
      user_id: 1,
      email: "a6-upsert@example.test",
      email_initial: "A",
      latitude: 52.52,
      longitude: 13.405,
      timestamp: 1700000000,
      updated_at: "2023-11-14T23:13:20+01:00",
    },
  },
]
const trackPayload = {
  id: 409,
  start_at: "2023-11-14T23:00:00+01:00",
  end_at: "2023-11-14T23:30:00+01:00",
  distance: 1500,
  avg_speed: 25,
  duration: 1800,
  elevation_gain: 50,
  elevation_loss: 20,
  elevation_max: 100,
  elevation_min: 50,
  original_path: "LINESTRING (13 52, 14 53)",
}
const trackOracles = [
  {
    source:
      "app/models/track.rb#broadcast_geojson_updated / app/serializers/tracks/geojson_serializer.rb",
    spec: "spec/models/track_spec.rb",
    example: "broadcasts the complete geojson_updated feature",
    payload: {
      action: "geojson_updated",
      track: {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: [
            [13, 52],
            [14, 53],
          ],
        },
        properties: {
          id: 409,
          color: "#6366F1",
          start_at: "2023-11-14T23:00:00+01:00",
          end_at: "2023-11-14T23:30:00+01:00",
          distance: 1500,
          avg_speed: 25,
          duration: 1800,
          revision: 0,
          dominant_mode: "walking",
          dominant_mode_emoji: "🚶",
          mode_timeline: [],
        },
      },
    },
  },
  {
    source:
      "app/models/track.rb#broadcast_track_created / app/serializers/track_serializer.rb",
    spec: "spec/models/track_spec.rb",
    example: "broadcasts the complete created track serializer payload",
    payload: { action: "created", track: trackPayload },
  },
  {
    source:
      "app/models/track.rb#broadcast_track_updated / app/serializers/track_serializer.rb",
    spec: "spec/models/track_spec.rb",
    example: "broadcasts the complete updated track serializer payload",
    payload: { action: "updated", track: trackPayload },
  },
  {
    source: "app/models/track.rb#broadcast_track_destroyed",
    spec: "spec/models/track_spec.rb",
    example: "broadcasts the destroyed track id",
    payload: { action: "destroyed", track_id: 409 },
  },
]
const editOracle = {
  source: "app/services/map_edits/publisher.rb.call",
  spec: "spec/services/map_edits/publisher_spec.rb",
  example: "publishes one versioned canonical point_moved event",
  payload: {
    type: "point_moved",
    version: 1,
    data: {
      point: { id: 405 },
      track: null,
      revision: { point: 1, track: null },
    },
  },
}

function channels(t, live = true, family = true) {
  created.length = 0
  const originalDocument = globalThis.document
  globalThis.document = {
    querySelector: () => ({
      dataset: { familyMembersFeaturesValue: JSON.stringify({ family }) },
    }),
  }
  t.after(() => {
    globalThis.document = originalDocument
  })
  const messages = []
  const connected = []
  const disconnected = []
  const result = createMapChannel({
    enableLiveMode: live,
    received: (data) => messages.push(data),
    connected: (name) => connected.push(name),
    disconnected: (name) => disconnected.push(name),
  })
  return { result, messages, connected, disconnected }
}

test("live mode and family features control only their own subscriptions", (t) => {
  for (const live of [false, true]) {
    for (const family of [false, true]) {
      const { connected, disconnected } = channels(t, live, family)
      const names = ["TracksChannel", "MapEditsChannel"]
      if (live) names.push("PointsChannel")
      if (family) names.push("FamilyLocationsChannel")
      assert.deepEqual(created.map((sub) => sub.name).sort(), names.sort())
      for (const subscription of created) {
        subscription.callbacks.connected()
        subscription.callbacks.disconnected()
      }
      const keys = ["tracks", "mapEdits"]
      if (live) keys.push("points")
      if (family) keys.push("family")
      assert.deepEqual(connected.sort(), keys.sort())
      assert.deepEqual(disconnected.sort(), keys.sort())
    }
  }
})

test("point messages preserve all eight tuple fields", (t) => {
  const { messages } = channels(t)
  for (const oracle of [pointOracle, upsertOracle]) {
    created
      .find((sub) => sub.name === "PointsChannel")
      .callbacks.received(oracle.payload)
    assert.deepEqual(messages.pop(), {
      type: "new_point",
      point: oracle.payload,
    })
  }
})

test("family messages preserve the member object", (t) => {
  const { messages } = channels(t)
  for (const oracle of familyOracles) {
    created
      .find((sub) => sub.name === "FamilyLocationsChannel")
      .callbacks.received(oracle.payload)
    assert.deepEqual(messages.pop(), {
      type: "family_location",
      member: oracle.payload,
    })
  }
})

test("track messages preserve action feature and destroyed track id", (t) => {
  const { messages } = channels(t)
  for (const oracle of trackOracles) {
    created
      .find((sub) => sub.name === "TracksChannel")
      .callbacks.received(oracle.payload)
    assert.deepEqual(messages.pop(), {
      type: "track_update",
      action: oracle.payload.action,
      track: oracle.payload.track,
      track_id: oracle.payload.track_id,
    })
  }
})

test("map edit messages preserve version and serialized data", (t) => {
  const { messages } = channels(t)
  created
    .find((sub) => sub.name === "MapEditsChannel")
    .callbacks.received(editOracle.payload)
  assert.deepEqual(messages, [{ type: "map_edit", event: editOracle.payload }])
})

test("unsubscribeAll releases every created subscription", (t) => {
  const { result } = channels(t)
  result.unsubscribeAll()
  assert.deepEqual(
    created.map((sub) => sub.unsubscribes),
    [1, 1, 1, 1],
  )
  result.unsubscribeAll()
  assert.deepEqual(
    created.map((sub) => sub.unsubscribes),
    [2, 2, 2, 2],
  )
  withoutConsumer()
  const absent = createMapChannel({ enableLiveMode: true })
  assert.deepEqual(absent.subscriptions, {
    family: null,
    points: null,
    tracks: null,
    mapEdits: null,
  })
  assert.doesNotThrow(() => absent.unsubscribeAll())
})
