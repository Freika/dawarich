import assert from "node:assert/strict"
import test from "node:test"
import { FamilyConfirm } from "../../app-phoenix/assets/js/hooks/family_confirm.js"
import { FamilyInvitationClipboard } from "../../app-phoenix/assets/js/hooks/family_invitation_clipboard.js"

function element(dataset = {}) {
  const listeners = new Map()
  return {
    dataset,
    listeners,
    open: true,
    disabled: false,
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name, fn) => {
      if (listeners.get(name) === fn) listeners.delete(name)
    },
    close() {
      this.open = false
      listeners.get("close")?.()
    },
  }
}
function mount(hook, el, extras = {}) {
  const instance = { ...hook, el, ...extras }
  instance.mounted()
  return instance
}
const tick = () => new Promise((resolve) => setImmediate(resolve))

test("escape cancels pending confirmation and destruction removes every listener", () => {
  const el = element({ pending: "true" })
  const events = []
  const hook = mount(FamilyConfirm, el, {
    pushEvent: (name) => events.push(name),
  })
  el.listeners.get("cancel")({ preventDefault() {} })
  assert.deepEqual(events, ["family_cancel_confirm"])
  hook.destroyed()
  assert.equal(el.listeners.size, 0)
  assert.equal(el.open, false)
})

test("clipboard permission failure is visible and navigation discards a late reveal", async () => {
  const status = { textContent: "" }
  globalThis.document = {
    querySelector: () => ({ content: "csrf" }),
    getElementById: () => status,
  }
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      clipboard: {
        writeText: async () => {
          throw Error("denied")
        },
      },
    },
  })
  const el = element({
    revealPath: "/native/family/invitations/1/copy",
    statusId: "status",
    copiedLabel: "copied",
    failedLabel: "failed",
  })
  let resolve
  globalThis.fetch = async () => ({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "transient-capability",
  })
  const hook = mount(FamilyInvitationClipboard, el)
  await hook.copy({ preventDefault() {} })
  assert.equal(status.textContent, "failed")
  let writes = 0
  navigator.clipboard.writeText = async () => {
    writes++
  }
  globalThis.fetch = () =>
    new Promise((done) => {
      resolve = done
    })
  const pending = hook.copy({ preventDefault() {} })
  await tick()
  hook.beforeUpdate()
  resolve({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "late-capability",
  })
  await pending
  assert.equal(writes, 0)
  assert.equal(status.textContent, "")
  assert.equal(el.disabled, false)
  hook.destroyed()
  assert.equal(el.listeners.size, 0)
  assert.equal(JSON.stringify(hook).includes("capability"), false)
})
