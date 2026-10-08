import assert from "node:assert/strict"
import test from "node:test"

const { AchievementUnlocks } = await import(
  "../../app-phoenix/assets/js/hooks/achievement_unlocks.js"
)

function fixture(t, respond) {
  const timers = []
  const storage = new Map()
  const globals = {
    document: { hidden: false, querySelector: () => null },
    sessionStorage: {
      getItem: (key) => storage.get(key) || null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    fetch: () => respond(),
    setTimeout: (fn, ms) => timers.push({ fn, ms }),
  }
  for (const [key, value] of Object.entries(globals)) {
    const original = Object.getOwnPropertyDescriptor(globalThis, key)
    Object.defineProperty(globalThis, key, { configurable: true, value })
    t.after(() => {
      if (original) Object.defineProperty(globalThis, key, original)
      else delete globalThis[key]
    })
  }
  t.mock.method(console, "error", () => {})

  const hook = Object.assign(Object.create(AchievementUnlocks), {
    el: { dataset: { seenUrl: "/achievements/unlocks/__ID__/seen" } },
    stopped: false,
    storageKey: "claim",
    saved: { token: "t" },
    current: { id: 7, token: "t" },
  })
  return { hook, timers }
}

test("a stale claim answered with 409 ends the acknowledgement without retrying", async (t) => {
  const { hook, timers } = fixture(t, async () => ({ ok: false, status: 409 }))

  assert.equal(await hook.acknowledge(), true)
  assert.equal(hook.current.token, null)
  assert.equal(timers.length, 0)
})

test("a failed acknowledgement retries while the hook is alive", async (t) => {
  const { hook, timers } = fixture(t, async () => ({ ok: false, status: 500 }))

  assert.equal(await hook.acknowledge(), false)
  assert.equal(timers.length, 1)
  assert.equal(hook.current.token, "t")
})

test("a failure that lands after the hook is destroyed schedules no retry", async (t) => {
  let fail
  const { hook, timers } = fixture(
    t,
    () =>
      new Promise((resolve) => {
        fail = () => resolve({ ok: false, status: 500 })
      }),
  )

  const pending = hook.acknowledge()
  hook.stopped = true
  fail()

  assert.equal(await pending, false)
  assert.equal(timers.length, 0)
  assert.equal(await hook.acknowledge(), false)
})
