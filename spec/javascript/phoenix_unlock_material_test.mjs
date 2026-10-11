import assert from "node:assert/strict"
import test from "node:test"
import { AchievementUnlocksLifecycle } from "../../app-phoenix/assets/js/hooks/achievement_unlocks.js"

test("unlock reveal initializes spectral material and releases it when hidden", async () => {
  const el = { replaceChildren() {} }
  let initialized = 0
  let disposed = 0
  const runtime = new AchievementUnlocksLifecycle(el, async () => ({
    initializeAchievementMaterials(root) {
      assert.equal(root, el)
      initialized++
      return () => disposed++
    },
  }))
  runtime.epoch = 1
  runtime.storageKey = "synthetic-material"
  await runtime.decorate(1)
  assert.equal(initialized, 1)
  runtime.hide()
  assert.equal(disposed, 1)
})

test("a late spectral loader cannot decorate a destroyed or replaced unlock deck", async () => {
  for (const boundary of ["destroyed", "replaced"]) {
    let resolve
    let initialized = 0
    const runtime = new AchievementUnlocksLifecycle(
      {},
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    runtime.epoch = 1
    const pending = runtime.decorate(1)
    if (boundary === "destroyed") runtime.stopped = true
    else runtime.epoch = 2
    resolve({ initializeAchievementMaterials: () => initialized++ })
    await pending
    assert.equal(initialized, 0)
  }
})
