import assert from "node:assert/strict"
import { test } from "node:test"
import { createOnboardingDialog } from "../../app-phoenix/assets/js/onboarding/dialog.js"

function fixture({ auto = true, opens = true, stored = {} } = {}) {
  const listeners = new Map()
  const pushed = []
  const queue = []
  const storage = {
    data: { ...stored },
    getItem(key) {
      return this.data[key] ?? null
    },
    setItem(key, value) {
      this.data[key] = value
    },
  }
  const dialog = {
    open: false,
    showModal() {
      this.open = opens
    },
    addEventListener: (type, fn) => listeners.set(type, fn),
    removeEventListener: (type, fn) =>
      listeners.get(type) === fn && listeners.delete(type),
  }
  const owner = createOnboardingDialog({
    dialog,
    auto,
    userId: "7",
    storage,
    timers: {
      setTimeout: (fn) => queue.push(fn) && queue.length,
      clearTimeout: (id) => {
        queue[id - 1] = null
      },
    },
    complete: () => pushed.push("onboarding:complete"),
  })
  const flush = () => {
    for (const fn of queue.splice(0)) fn?.()
  }
  return { owner, dialog, listeners, pushed, storage, flush }
}

test("only eligible map auto-opens once after successful showModal", () => {
  const failed = fixture({ opens: false })
  failed.owner.start()
  failed.flush()
  assert.equal(failed.storage.getItem("dawarich_onboarding_shown_7"), null)
  assert.equal(failed.listeners.size, 0)

  const manual = fixture({ auto: false })
  manual.owner.start()
  manual.flush()
  assert.equal(manual.dialog.open, false)

  const seen = fixture({ stored: { dawarich_onboarding_shown_7: "true" } })
  seen.owner.start()
  seen.flush()
  assert.equal(seen.dialog.open, false)

  const fresh = fixture()
  fresh.owner.start()
  assert.equal(fresh.dialog.open, false)
  fresh.flush()
  assert.equal(fresh.dialog.open, true)
  assert.equal(fresh.storage.getItem("dawarich_onboarding_shown_7"), "true")
})

test("auto-open close persists completion but manual close keeps chosen semantics", () => {
  const auto = fixture()
  auto.owner.start()
  auto.flush()
  auto.listeners.get("close")()
  assert.deepEqual(auto.pushed, ["onboarding:complete"])
  assert.equal(auto.listeners.size, 0)

  const manual = fixture({ auto: false })
  manual.owner.start()
  manual.flush()
  manual.dialog.showModal()
  assert.equal(manual.listeners.size, 0)
  assert.deepEqual(manual.pushed, [])
})

test("destroy does not complete onboarding or retain listeners", () => {
  const pending = fixture()
  pending.owner.start()
  pending.owner.destroy()
  pending.flush()
  assert.equal(pending.dialog.open, false)

  const shown = fixture()
  shown.owner.start()
  shown.flush()
  shown.owner.destroy()
  assert.equal(shown.listeners.size, 0)
  assert.deepEqual(shown.pushed, [])

  const blocked = fixture()
  blocked.storage.getItem = () => {
    throw new Error("blocked")
  }
  blocked.owner.start()
  blocked.flush()
  assert.equal(blocked.dialog.open, true)
})
