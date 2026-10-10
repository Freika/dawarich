import assert from "node:assert/strict"
import test from "node:test"
import { readRouteSnapshot } from "../../app-phoenix/assets/js/map/data/route_snapshot.js"

test("map replay snapshot reads photos only when enabled using its scoped range and cancellation", async () => {
  const calls = [],
    signal = new AbortController().signal
  const reader = {
    async pages(resource, params, options) {
      calls.push({ resource, params, options })
      return resource === "photos" ? [{ id: 1 }] : []
    },
  }
  const state = {
    photosEnabled: true,
    range: {
      startAt: "2026-03-29T00:00",
      endAt: "2026-03-30T23:59",
      importId: 7,
    },
  }
  const data = await readRouteSnapshot(reader, state, {
    purpose: "replay",
    signal,
  })
  assert.deepEqual(data.photos, [{ id: 1 }])
  assert.deepEqual(calls[1], {
    resource: "photos",
    params: {
      start_at: state.range.startAt,
      end_at: state.range.endAt,
      import_id: 7,
    },
    options: { signal },
  })
  calls.length = 0
  assert.deepEqual(
    (
      await readRouteSnapshot(
        reader,
        { ...state, photosEnabled: false },
        { purpose: "replay", signal },
      )
    ).photos,
    [],
  )
  assert.equal(calls.length, 1)
})
