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

test("offscreen achievement cards wait for the Rails 160px visibility margin", async (t) => {
  const previous = globalThis.IntersectionObserver
  let visible, options, disconnected = 0, imports = 0, mounts = 0
  globalThis.IntersectionObserver = class {
    constructor(callback, config) { visible = callback; options = config }
    observe() {}
    disconnect() { disconnected++ }
  }
  t.after(() => { globalThis.IntersectionObserver = previous })
  const hook = { ...AchievementMaterial, el: {}, loader: async () => {
    imports++
    return { initializeAchievementCard() { mounts++; return () => {} } }
  } }
  await hook.mounted()
  assert.equal(imports, 0)
  assert.deepEqual(options, { rootMargin: "160px" })
  visible([{ isIntersecting: false }])
  assert.equal(imports, 0)
  await visible([{ isIntersecting: true }])
  assert.equal(imports, 1)
  assert.equal(mounts, 1)
  hook.destroyed()
  assert.ok(disconnected > 0)
})

test("material visibility observes the card box rather than its display-contents slot", async (t) => {
  const previous = globalThis.IntersectionObserver
  const card = {}, observed = []
  globalThis.IntersectionObserver = class {
    constructor() {}
    observe(element) { observed.push(element) }
    disconnect() {}
  }
  t.after(() => { globalThis.IntersectionObserver = previous })
  const hook = {
    ...AchievementMaterial,
    el: { closest(selector) { return selector === ".ach-card-wrap" ? card : null } },
  }
  await hook.mounted()
  assert.deepEqual(observed, [card])
  hook.destroyed()
})
