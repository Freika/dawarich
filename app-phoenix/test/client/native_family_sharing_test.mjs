import assert from "node:assert/strict"
import test from "node:test"
import { FamilySharing, FamilyInviteScroll } from "../../assets/js/hooks/family_sharing.js"

function mount(event = "family:sharing") {
  const listeners = new Map()
  const inputs = {
    enabled: { value: "false" }, duration: { value: "1h" },
    share_history: { value: "true" }, history_window: { value: "30d" },
  }
  const events = []
  const el = {
    dataset: { nativeSharingEvent: event },
    querySelector: (selector) => inputs[selector.match(/name="([^"]+)"/)[1]],
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name, fn) => { assert.equal(listeners.get(name), fn); listeners.delete(name) },
  }
  const hook = { ...FamilySharing, el, pushEvent: (...args) => events.push(args) }
  hook.mounted()
  return { hook, events, listeners }
}

test("native family sharing sends the changed consent field with the visible independent settings", () => {
  for (const [field, type, value, checked, expected] of [
    ["enabled", "checkbox", "on", true, "true"],
    ["share_history", "checkbox", "on", false, "false"],
    ["duration", "select-one", "6h", false, "6h"],
    ["history_window", "select-one", "7d", false, "7d"],
  ]) {
    const { hook, events, listeners } = mount()
    listeners.get("change")({ target: { dataset: { nativeSharingField: field }, type, value, checked } })
    assert.deepEqual(events, [["family:sharing", { sharing: { enabled: "false", duration: "1h", share_history: "true", history_window: "30d", [field]: expected } }]])
    hook.destroyed()
    assert.equal(listeners.size, 0)
  }
})

test("native lapsed family sharing uses its admitted command and teardown prevents form submission", () => {
  const { hook, events, listeners } = mount("family_set_sharing")
  let prevented = false
  listeners.get("submit")({ preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  listeners.get("change")({ target: { dataset: { nativeSharingField: "enabled" }, type: "checkbox", checked: false } })
  assert.deepEqual(events, [["family_set_sharing", { enabled: "false", duration: "1h", share_history: "true", history_window: "30d" }]])
  hook.destroyed()
  assert.equal(listeners.size, 0)
})

test("native family invite scroll owns its click listener and uses the Rails smooth target", () => {
  const listeners = new Map(), scrolls = []
  const target = { scrollIntoView: (value) => scrolls.push(value) }
  const el = { ownerDocument: { getElementById: (id) => { assert.equal(id, "invite-section"); return target } }, addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: (name, fn) => { assert.equal(listeners.get(name), fn); listeners.delete(name) } }
  const hook = { ...FamilyInviteScroll, el }
  hook.mounted()
  listeners.get("click")()
  assert.deepEqual(scrolls, [{ behavior: "smooth" }])
  hook.destroyed()
  assert.equal(listeners.size, 0)
})
