import assert from "node:assert/strict"
import test from "node:test"
import { ApiClient } from "maps_maplibre/services/api_client"

function recordFetch(t, response) {
  const calls = []
  t.mock.method(globalThis, "fetch", async (url, options) => {
    calls.push({ url, ...options })
    return response
  })
  return calls
}

test("a visit write sends its method, path and JSON body", async (t) => {
  const calls = recordFetch(t, { ok: true, json: async () => ({ id: 3 }) })
  const api = new ApiClient("key")

  assert.deepEqual(await api.bulkUpdateVisits([3, 4], "confirmed"), { id: 3 })
  await api.deleteVisit(3)

  assert.equal(calls[0].url, "/api/v1/visits/bulk_update")
  assert.equal(calls[0].method, "POST")
  assert.deepEqual(JSON.parse(calls[0].body), {
    visit_ids: [3, 4],
    status: "confirmed",
  })
  assert.equal(calls[1].url, "/api/v1/visits/3")
  assert.equal(calls[1].method, "DELETE")
  assert.equal("body" in calls[1], false)
})

test("a failed write throws with the action and status text", async (t) => {
  recordFetch(t, { ok: false, statusText: "Unprocessable Entity" })

  await assert.rejects(new ApiClient("key").markPointValid(7), {
    message: "Failed to mark point as correct: Unprocessable Entity",
  })
})
