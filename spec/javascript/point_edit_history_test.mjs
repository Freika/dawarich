import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/editing/point_edit_history.js",
    import.meta.url,
  ),
  "utf8",
)
const { PointEditHistory } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

// A fake server: every move bumps the point revision and, for a track point,
// the track revision, and rejects stale revisions the way Points::Move does.
function fakeServer() {
  const points = new Map()
  const tracks = new Map()
  const requests = []
  const server = {
    requests,
    seed(pointId, { trackId = null, revision = 1, trackRevision = 1 } = {}) {
      points.set(pointId, { revision, trackId })
      if (trackId != null) tracks.set(trackId, trackRevision)
    },
    touch(pointId) {
      const point = points.get(pointId)
      point.revision += 1
      if (point.trackId != null)
        tracks.set(point.trackId, tracks.get(point.trackId) + 1)
    },
    async move(pointId, position) {
      requests.push({ pointId, ...position })
      const point = points.get(pointId)
      const stale =
        point.revision !== position.pointRevision ||
        (point.trackId != null &&
          tracks.get(point.trackId) !== position.trackRevision)
      if (stale) {
        const error = new Error("conflict")
        error.status = 409
        throw error
      }
      server.touch(pointId)
      return server.response(pointId, position)
    },
    response(pointId, { longitude, latitude }) {
      const point = points.get(pointId)
      return {
        point: { id: pointId, longitude, latitude, revision: point.revision },
        track:
          point.trackId == null ? null : { properties: { id: point.trackId } },
        revision: {
          point: point.revision,
          track: point.trackId == null ? null : tracks.get(point.trackId),
        },
      }
    },
  }
  return server
}

function moveAndRecord(history, server, pointId, from, to) {
  server.touch(pointId)
  history.record({ pointId, from, to }, server.response(pointId, to))
}

const A = { longitude: 0, latitude: 0 }
const B = { longitude: 1, latitude: 1 }
const C = { longitude: 2, latitude: 2 }

test("undo moves the point back, and redo moves it forward again", async () => {
  const server = fakeServer()
  server.seed(7)
  const history = new PointEditHistory({ move: server.move })
  moveAndRecord(history, server, 7, A, B)

  await history.undo()
  assert.deepEqual(server.requests.at(-1), {
    pointId: 7,
    ...A,
    pointRevision: 2,
    trackRevision: null,
  })
  assert.equal(history.canUndo, false)
  assert.equal(history.canRedo, true)

  await history.redo()
  assert.deepEqual(server.requests.at(-1), {
    pointId: 7,
    ...B,
    pointRevision: 3,
    trackRevision: null,
  })
  assert.equal(history.canRedo, false)
})

test("undoing several edits of one track uses the track's latest revision each time", async () => {
  const server = fakeServer()
  server.seed(1, { trackId: 10 })
  server.seed(2, { trackId: 10 })
  const history = new PointEditHistory({ move: server.move })
  moveAndRecord(history, server, 1, A, B)
  moveAndRecord(history, server, 2, B, C)

  await history.undo()
  await history.undo()

  assert.equal(server.requests.length, 2)
  assert.deepEqual(
    server.requests.map((request) => [request.pointId, request.longitude]),
    [
      [2, B.longitude],
      [1, A.longitude],
    ],
  )
  assert.equal(history.canUndo, false)
})

test("a new edit after an undo discards what could be redone", async () => {
  const server = fakeServer()
  server.seed(7)
  const history = new PointEditHistory({ move: server.move })
  moveAndRecord(history, server, 7, A, B)
  await history.undo()

  moveAndRecord(history, server, 7, A, C)

  assert.equal(history.canRedo, false)
  assert.equal(history.entries.length, 1)
})

test("only the five latest edits are kept", () => {
  const server = fakeServer()
  const history = new PointEditHistory({ move: server.move })
  for (let id = 1; id <= 7; id += 1) {
    server.seed(id)
    moveAndRecord(history, server, id, A, B)
  }

  assert.deepEqual(
    history.entries.map((entry) => entry.pointId),
    [3, 4, 5, 6, 7],
  )
  assert.equal(history.limit, 5)
  assert.equal(history.size, 5)
})

test("undone edits still count towards the kept moves", async () => {
  const server = fakeServer()
  server.seed(7)
  const history = new PointEditHistory({ move: server.move })
  moveAndRecord(history, server, 7, A, B)
  assert.equal(history.size, 1)

  await history.undo()

  assert.equal(history.size, 1)
})

test("an edit that lost to a change made elsewhere is dropped and the error passed on", async () => {
  const server = fakeServer()
  server.seed(7)
  const history = new PointEditHistory({ move: server.move })
  moveAndRecord(history, server, 7, A, B)
  server.touch(7)

  await assert.rejects(history.undo(), (error) => error.status === 409)

  assert.equal(history.canUndo, false)
  assert.equal(history.canRedo, false)
})

test("a failed request keeps the edit so it can be tried again", async () => {
  const server = fakeServer()
  server.seed(7)
  let fail = true
  const history = new PointEditHistory({
    move: (id, position) => {
      if (fail) return Promise.reject(new Error("offline"))
      return server.move(id, position)
    },
  })
  moveAndRecord(history, server, 7, A, B)

  await assert.rejects(history.undo())
  assert.equal(history.canUndo, true)

  fail = false
  await history.undo()
  assert.equal(history.canRedo, true)
})

test("stepping back to an entry undoes every newer edit, and forward redoes them", async () => {
  const server = fakeServer()
  for (const id of [1, 2, 3]) server.seed(id)
  const history = new PointEditHistory({ move: server.move })
  moveAndRecord(history, server, 1, A, B)
  moveAndRecord(history, server, 2, A, B)
  moveAndRecord(history, server, 3, A, B)
  const first = history.entries[0]

  await history.travelTo(first)
  assert.deepEqual(
    server.requests.map((request) => request.pointId),
    [3, 2, 1],
  )
  assert.equal(history.canUndo, false)

  await history.travelTo(history.undone.at(-2))
  assert.deepEqual(
    server.requests.slice(3).map((request) => request.pointId),
    [1, 2],
  )
  assert.equal(history.entries.length, 2)
})

test("listeners hear every change, and a step is ignored while another is saving", async () => {
  const server = fakeServer()
  server.seed(7)
  server.seed(8)
  let changes = 0
  const history = new PointEditHistory({
    move: server.move,
    onChange: () => {
      changes += 1
    },
  })
  moveAndRecord(history, server, 7, A, B)
  moveAndRecord(history, server, 8, A, B)

  const first = history.undo()
  assert.equal(history.busy, true)
  await Promise.all([first, history.undo()])

  assert.deepEqual(
    server.requests.map((request) => request.pointId),
    [8],
  )
  assert.equal(history.busy, false)
  assert.ok(changes >= 4)
})
