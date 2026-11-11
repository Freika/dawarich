import assert from "node:assert/strict"
import test from "node:test"
import { strippedSource } from "./support/stripped_source.mjs"

// announceEmptyTracks() reads only the controller's range statistics and the
// toast, so it runs against a plain context with stubbed imports.
const stubs = `
const toasts = []
const Toast = { info: (message) => toasts.push(message) }
const translate = (key) => key
export { toasts }
`
const source = await strippedSource(
  "controllers/maps/maplibre/layer_manager.js",
)
const { LayerManager, toasts } = await import(
  `data:text/javascript;base64,${Buffer.from(stubs + source).toString("base64")}`
)

function announce(rangeStatistics) {
  toasts.length = 0
  return LayerManager.prototype.announceEmptyTracks.call({
    controller: { rangeStatistics },
  })
}

test("an empty period gets no tracks-pending toast", async () => {
  await announce({ pending: Promise.resolve(), data: { points: 0 } })
  assert.deepEqual(toasts, [])
})

test("a period with points but no tracks gets the toast", async () => {
  await announce({ pending: Promise.resolve(), data: { points: 40 } })
  assert.deepEqual(toasts, ["messages.tracks_pending"])
})

test("waits for a newer range load that replaced the pending one", async () => {
  let finishNewer
  const statistics = { data: null }
  const newer = new Promise((resolve) => {
    finishNewer = resolve
  })
  statistics.pending = Promise.reject(new Error("aborted")).finally(() => {
    statistics.pending = newer
  })
  const announced = announce(statistics)
  await new Promise((resolve) => setTimeout(resolve, 0))
  statistics.data = { points: 0 }
  finishNewer()
  await announced
  assert.deepEqual(toasts, [])
})
