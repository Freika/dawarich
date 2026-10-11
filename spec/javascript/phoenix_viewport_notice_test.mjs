import assert from "node:assert/strict"
import test from "node:test"
import { createViewportFit } from "../../app-phoenix/assets/js/map/runtime/viewport_fit.js"

test("native bounds keep points above an overlapping demo banner and release retired clearance", async () => {
  let notice = { left: 400, right: 880, top: 650, bottom: 704 }
  const calls = []
  const element = {
    closest: () => ({ querySelector: () => null }),
    ownerDocument: {
      querySelector: () => ({ getBoundingClientRect: () => notice }),
    },
  }
  const map = {
    getContainer: () => ({
      getBoundingClientRect: () => ({
        left: 0,
        right: 1280,
        top: 475,
        bottom: 720,
      }),
    }),
    fitBounds: (_bounds, options) => calls.push(options),
  }
  const fit = createViewportFit(
    {
      read: async () => ({
        status: "ok",
        data: { min_lng: 13, max_lng: 14, min_lat: 52, max_lat: 53 },
      }),
    },
    element,
  )
  const operation = { wait: async (promise) => promise, check() {} }
  const config = { range: { startAt: "start", endAt: "end" } }
  await fit({ map, config, operation })
  assert.equal(calls[0].padding.bottom, 82)
  assert.equal(calls[0].padding.left, 50)
  notice = { left: 0, right: 0, top: 0, bottom: 0 }
  await fit({ map, config: { ...config, epoch: 1 }, operation })
  assert.equal(calls[1].padding.bottom, 50)
  notice = { left: 1300, right: 1500, top: 650, bottom: 704 }
  await fit({ map, config: { ...config, epoch: 2 }, operation })
  assert.equal(calls[2].padding.bottom, 50)
})
