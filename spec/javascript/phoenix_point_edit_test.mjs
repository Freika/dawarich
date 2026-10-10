import assert from "node:assert/strict"
import { test } from "node:test"
import { createPointEditing } from "../../app-phoenix/assets/js/map/edit/runtime.js"

function fixture({ editMode = true } = {}) {
  const pushed = []
  const positions = []
  const detached = []
  const editing = createPointEditing({
    isEditMode: () => editMode,
    pushEvent: (event, payload, reply) =>
      pushed.push({ event, payload, reply }),
    setPosition: (pointId, position) => positions.push([pointId, position]),
    gesture: { detach: () => detached.push(true) },
  })
  return { editing, pushed, positions, detached }
}

const move = {
  pointId: 5,
  from: { latitude: 52.5, longitude: 13.4 },
  to: { latitude: 52.6, longitude: 13.5 },
  pointRevision: 2,
  trackRevision: 4,
  historyScope: { startAt: "2026-03-29T00:00", endAt: "2026-03-29T23:59" },
}

const accepted = {
  ok: true,
  response: {
    point: { id: 5, revision: 3 },
    track: { properties: { id: 9, revision: 5 } },
    revision: { point: 3, track: 5 },
  },
}

test("drag without edit mode cannot persist", async () => {
  const { editing, pushed, positions } = fixture({ editMode: false })
  assert.deepEqual(await editing.commit(move), { status: "refused" })
  assert.equal(pushed.length, 0)
  assert.deepEqual(positions, [[5, move.from]])
  assert.equal(editing.history.size, 0)
})

test("conflict restores coordinates and leaves history unchanged", async () => {
  const { editing, pushed, positions } = fixture()
  const first = editing.commit(move)
  assert.deepEqual(pushed[0].payload, {
    point_id: 5,
    point: { latitude: "52.6", longitude: "13.5", revision: 2 },
    track_revision: 4,
    history_scope: { start_at: "2026-03-29T00:00", end_at: "2026-03-29T23:59" },
  })
  pushed[0].reply(accepted)
  assert.deepEqual(await first, { status: "saved" })
  assert.equal(editing.history.size, 1)

  const second = editing.commit({
    ...move,
    from: move.to,
    to: { latitude: 1, longitude: 1 },
  })
  pushed[1].reply({
    error: "stale",
    response: { point: { id: 5, revision: 7 } },
  })
  assert.deepEqual(await second, { status: "conflict" })
  assert.deepEqual(positions, [[5, move.to]])
  assert.equal(editing.history.size, 1)
})

test("destroy cancels drag and pending undo", async () => {
  const { editing, pushed, positions, detached } = fixture()
  const saved = editing.commit(move)
  pushed[0].reply(accepted)
  await saved

  const undo = editing.undo()
  assert.equal(pushed[1].event, "point:move")
  assert.equal(pushed[1].payload.point.revision, 3)
  editing.destroy()
  assert.deepEqual(detached, [true])
  await assert.rejects(undo, { name: "AbortError" })
  pushed[1].reply(accepted)
  assert.deepEqual(positions, [])
  assert.deepEqual(await editing.commit(move), { status: "refused" })
  assert.equal(pushed.length, 2)
})
