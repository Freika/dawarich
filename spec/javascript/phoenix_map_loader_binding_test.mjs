import assert from "node:assert/strict"
import test from "node:test"
import { MapHook } from "../../app-phoenix/assets/js/map/hooks/map.js"

test("native map lazy loader retains the owning hook for admission callbacks", async () => {
  const owner = { mount: async () => "ready", destroy() {} }
  const hook = {
    ...MapHook,
    el: { dataset: {} },
    handleEvent: name => name,
    removeHandleEvent() {},
    pushEvent() {},
    loader() {
      assert.equal(this, hook)
      return Promise.resolve({ mountHost: () => owner })
    },
  }
  try {
    await hook.mounted()
    assert.equal(hook.mapOwner, owner)
    assert.equal(hook.mapReady, true)
  } finally {
    hook.destroyed()
  }
})
