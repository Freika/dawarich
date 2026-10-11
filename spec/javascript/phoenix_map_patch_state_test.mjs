import assert from "node:assert/strict"
import test from "node:test"
import { MapHook } from "../../app-phoenix/assets/js/hooks/map.js"
import { MapPreview } from "../../app-phoenix/assets/js/hooks/map_preview.js"

for (const [kind, implementation] of [
  ["map", MapHook],
  ["preview", MapPreview],
]) {
  test(`a native ${kind} patch preserves the owned readiness state`, () => {
    const updates = []
    const hook = {
      ...implementation,
      el: {
        dataset: {
          mapState: "ready",
          mapConfig: JSON.stringify({ tripId: 2 }),
        },
      },
      previewOwner: { update: (config) => updates.push(config) },
    }
    hook.beforeUpdate()
    hook.el.dataset.mapState = "loading"
    hook.updated()
    assert.equal(hook.el.dataset.mapState, "ready")
    if (kind === "preview") assert.deepEqual(updates, [{ tripId: 2 }])
    hook.el.dataset.mapState = "failed"
    hook.beforeUpdate()
    hook.el.dataset.mapState = "loading"
    hook.updated()
    assert.equal(hook.el.dataset.mapState, "failed")
  })
}

test("a completed native map refresh outranks an older patch snapshot", () => {
  const hook = {
    ...MapHook,
    el: { dataset: { mapState: "loading" } },
    mapOwner: { presentationState: "loading" },
  }
  hook.beforeUpdate()
  hook.mapOwner.presentationState = "ready"
  hook.updated()
  assert.equal(hook.el.dataset.mapState, "ready")
})
