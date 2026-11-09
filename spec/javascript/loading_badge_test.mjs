import assert from "node:assert/strict"
import test from "node:test"
import { LoadingBadge } from "controllers/maps/maplibre/loading_badge"

function classes() {
  const set = new Set()
  return {
    add: (...names) => {
      for (const n of names) set.add(n)
    },
    remove: (...names) => {
      for (const n of names) set.delete(n)
    },
    contains: (name) => set.has(name),
  }
}

// CI's Node 18.17 has no t.mock.timers; collect the badge's timeouts instead.
function fakeTimers(t) {
  const pending = []
  t.mock.method(globalThis, "setTimeout", (fn, ms) => {
    pending.push({ fn, ms })
  })
  return {
    tick(ms) {
      for (const timer of pending.splice(0)) {
        if (timer.ms <= ms) timer.fn()
        else pending.push({ ...timer, ms: timer.ms - ms })
      }
    },
  }
}

function badgeHarness(controllerExtras = {}) {
  const badge = { classList: classes(), offsetWidth: 0 }
  const text = { textContent: "" }
  const controller = {
    hasProgressBadgeTarget: true,
    progressBadgeTarget: badge,
    hasProgressBadgeTextTarget: true,
    progressBadgeTextTarget: text,
    ...controllerExtras,
  }
  return { loading: new LoadingBadge(controller), badge, text }
}

test("a source that finishes marks the badge complete and hides it", (t) => {
  const timers = fakeTimers(t)
  const { loading, badge, text } = badgeHarness()

  loading.start("points")
  assert.equal(badge.classList.contains("visible"), true)
  assert.equal(text.textContent, "loading_sources.points")

  loading.finish("points", 12)
  assert.equal(badge.classList.contains("complete"), true)
  timers.tick(1200)
  assert.equal(badge.classList.contains("visible"), false)
})

test("a badge no source completed is dismissed after a short delay", (t) => {
  const timers = fakeTimers(t)
  const { loading, badge } = badgeHarness()

  loading.show()
  loading.dismissIfIncomplete()
  timers.tick(799)
  assert.equal(badge.classList.contains("visible"), true)
  timers.tick(1)
  assert.equal(badge.classList.contains("visible"), false)
})

test("a completed badge is left to its own fade", (t) => {
  const timers = fakeTimers(t)
  const { loading, badge } = badgeHarness()

  loading.start("visits")
  loading.finish("visits", 3)
  loading.dismissIfIncomplete()
  timers.tick(800)
  assert.equal(badge.classList.contains("visible"), true)
})

test("family members are listed when the family layer is on", () => {
  const { loading, text } = badgeHarness({
    settings: { familyEnabled: true },
    familyManager: { memberCount: 2 },
  })

  loading.update({ counts: { points: 5 } })

  assert.equal(
    text.textContent,
    "loading_sources.points · loading_sources.family",
  )
})
