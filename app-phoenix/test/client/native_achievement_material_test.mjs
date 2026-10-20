import assert from "node:assert/strict"
import test from "node:test"
import { AchievementMaterial } from "../../assets/js/hooks/achievement_material.js"

test("native card material initializes lazily and releases its renderer on departure", async () => {
  const element = {}, calls = []
  const hook = { ...AchievementMaterial, el: element, loader: async () => ({ initializeAchievementCard(el) { assert.equal(el, element); calls.push("mount"); return () => calls.push("dispose") } }) }
  await hook.mounted()
  assert.deepEqual(calls, ["mount"])
  hook.destroyed()
  assert.deepEqual(calls, ["mount", "dispose"])
})

test("a discarded lazy card import never touches departed DOM", async () => {
  let loaded, mounts = 0
  const hook = { ...AchievementMaterial, el: {}, loader: () => new Promise((resolve) => { loaded = resolve }) }
  const mounting = hook.mounted()
  hook.destroyed()
  loaded({ initializeAchievementCard() { mounts++; return () => {} } })
  await mounting
  assert.equal(mounts, 0)
})
