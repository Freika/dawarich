import assert from "node:assert/strict"
import { test } from "node:test"
import { mountHost } from "../../app-phoenix/assets/js/map/runtime/host.js"

test("map host waits for configuration acknowledgement before publishing studio dates", async () => {
  const range = {
    startAt: "2026-04-01",
    endAt: "2026-04-02",
    timezone: "Europe/Berlin",
  }
  let reply
  const element = {
    dataset: { mapConfig: JSON.stringify({ revision: 1, range }) },
    appendChild() {},
    ownerDocument: { createElement: () => ({ style: {}, remove() {} }) },
  }
  const owner = mountHost({
    element,
    pushEvent: (_, __, callback) => {
      if (callback) reply = callback
    },
    reader: { reset() {}, destroy() {} },
    loadStyle: async () => ({}),
    loadLibrary: async () => ({
      Map: class {
        remove() {}
      },
    }),
    attach() {},
    refresh: async () => {},
  })
  try {
    const applying = owner.source.applyDates(range)
    let settled = false
    let failure
    applying.then(
      () => {
        settled = true
      },
      (error) => {
        failure = error
      },
    )
    reply({ revision: 2 })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(failure, undefined)
    assert.equal(settled, false)
    await owner.update({ revision: 2, range })
    assert.deepEqual(await applying, { revision: 2 })
  } finally {
    owner.destroy()
  }
})
