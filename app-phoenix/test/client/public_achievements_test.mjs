import assert from "node:assert/strict"
import test from "node:test"
import { setImmediate } from "node:timers/promises"
import { initializePublicAchievements } from "../../assets/js/public_achievements.js"

function fixture(count = 1) {
  const elements = Array.from({ length: count }, () => ({ innerHTML: "fallback" }))
  const listeners = new Map()
  const root = { querySelectorAll(selector) {
    assert.equal(selector, '.spectral-material[phx-hook="AchievementMaterial"]')
    return elements
  } }
  const target = {
    addEventListener(name, fn) { listeners.set(name, fn) },
    removeEventListener(name, fn) { if (listeners.get(name) === fn) listeners.delete(name) },
  }
  return { root, target, elements, listeners, hide(persisted = false) { listeners.get("pagehide")?.({ persisted }) } }
}

test("public documents lazily initialize every native material and dispose once on pagehide", async () => {
  const f = fixture(2), mounted = [], disposed = []
  let loads = 0
  const stop = initializePublicAchievements(f.root, f.target, async () => {
    loads++
    return { initializeAchievementCard(el) {
      mounted.push(el)
      el.innerHTML = "material"
      return () => disposed.push(el)
    } }
  })
  assert.equal(loads, 1)
  await setImmediate()
  assert.deepEqual(mounted, f.elements)
  f.hide()
  assert.deepEqual(disposed, f.elements)
  assert.deepEqual(f.elements.map(el => el.innerHTML), ["fallback", "fallback"])
  stop()
  stop()
  assert.equal(disposed.length, 2)
  assert.equal(f.listeners.size, 0)
  const empty = fixture(0)
  let emptyLoads = 0
  const stopEmpty = initializePublicAchievements(empty.root, empty.target, () => { emptyLoads++ })
  assert.equal(emptyLoads, 0)
  stopEmpty()
  assert.equal(empty.listeners.size, 0)
})

test("public pagehide retires a pending material import without touching departed DOM", async () => {
  const f = fixture()
  let loaded, mounts = 0
  const stop = initializePublicAchievements(f.root, f.target, () => new Promise(resolve => { loaded = resolve }))
  assert.equal(typeof loaded, "function")
  f.hide()
  loaded({ initializeAchievementCard() { mounts++; return () => {} } })
  await setImmediate()
  assert.equal(mounts, 0)
  stop()
})

test("cached public documents release material observers and remount from fallback on pageshow", async () => {
  const f = fixture(), calls = []
  const stop = initializePublicAchievements(f.root, f.target, async () => ({
    initializeAchievementCard(el) {
      assert.equal(el.innerHTML, "fallback")
      calls.push("mount")
      el.innerHTML = "material"
      return () => calls.push("dispose")
    },
  }))
  await setImmediate()
  assert.deepEqual(calls, ["mount"])
  f.hide(true)
  assert.deepEqual(calls, ["mount", "dispose"])
  f.listeners.get("pageshow")?.({ persisted: true })
  await setImmediate()
  assert.deepEqual(calls, ["mount", "dispose", "mount"])
  stop()
  assert.deepEqual(calls, ["mount", "dispose", "mount", "dispose"])
})

test("an old material import cannot mount into a restored public document generation", async () => {
  const f = fixture(), pending = [], mounts = []
  const stop = initializePublicAchievements(f.root, f.target, () => new Promise(resolve => pending.push(resolve)))
  assert.equal(pending.length, 1)
  f.hide(true)
  f.listeners.get("pageshow")?.({ persisted: true })
  assert.equal(pending.length, 2)
  pending[0]({ initializeAchievementCard() { mounts.push("old"); return () => {} } })
  pending[1]({ initializeAchievementCard() { mounts.push("current"); return () => {} } })
  await setImmediate()
  assert.deepEqual(mounts, ["current"])
  stop()
})

test("failed public renderer imports preserve fallback and remain safe to retire", async () => {
  const f = fixture()
  let loads = 0
  const stop = initializePublicAchievements(f.root, f.target, async () => { loads++; throw new Error("unavailable") })
  await setImmediate()
  assert.equal(loads, 1)
  assert.equal(f.elements[0].innerHTML, "fallback")
  stop()
  assert.equal(f.listeners.size, 0)
})
