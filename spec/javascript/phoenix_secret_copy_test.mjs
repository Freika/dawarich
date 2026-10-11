import assert from "node:assert/strict"
import test from "node:test"
import { FamilyInvitationClipboard } from "../../app-phoenix/assets/js/hooks/family_invitation_clipboard.js"
import { SharingReveal } from "../../app-phoenix/assets/js/hooks/sharing_controls.js"

function setup(t, kind, api, fallback) {
  const originals = [
    "navigator",
    "window",
    "document",
    "fetch",
    "setTimeout",
    "clearTimeout",
  ].map((key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)])
  t.after(() => {
    for (const [key, value] of originals) {
      if (value) Object.defineProperty(globalThis, key, value)
      else delete globalThis[key]
    }
  })
  const areas = [],
    timers = new Map(),
    listeners = new Map(),
    events = new Map()
  let copies = 0
  const status = {
    textContent: "",
    insertAdjacentElement(_, area) {
      area.connected = true
    },
  }
  const button = {
    disabled: false,
    dataset: {
      revealPath: "/native/family/invitations/1/copy",
      statusId: "copy",
      copiedLabel: "copied",
      failedLabel: "manual recovery",
    },
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name) => listeners.delete(name),
  }
  globalThis.document = {
    querySelector: () => ({ content: "synthetic-csrf" }),
    getElementById: () => status,
    body: {
      appendChild: (area) => {
        area.connected = true
      },
      removeChild: (area) => {
        area.connected = false
      },
    },
    createElement: () => {
      const area = {
        value: "",
        style: {},
        connected: false,
        setAttribute(name, value) {
          this[name] = value
        },
        focus() {
          this.focused = true
        },
        select() {
          this.selected = true
        },
        setSelectionRange() {},
        remove() {
          this.connected = false
        },
      }
      areas.push(area)
      return area
    },
    execCommand: () => {
      copies++
      return fallback
    },
  }
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value:
      api === "absent"
        ? {}
        : {
            clipboard: {
              writeText: async () => {
                throw Error("denied")
              },
            },
          },
  })
  globalThis.window = { isSecureContext: true }
  globalThis.setTimeout = (fn, ms) => {
    const id = {}
    timers.set(id, { fn, ms })
    return id
  }
  globalThis.clearTimeout = (id) => timers.delete(id)
  globalThis.fetch = async () => ({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "synthetic-copy-secret",
  })
  const el =
    kind === "sharing"
      ? {
          dataset: {
            url: "/native/sharing/id/phrase",
            copiedLabel: "copied",
            failedLabel: "manual recovery",
          },
          querySelector: (selector) =>
            selector === "[data-reveal]" ? button : status,
        }
      : button
  const hook = {
    ...(kind === "sharing" ? SharingReveal : FamilyInvitationClipboard),
    el,
    handleEvent(name, fn) {
      events.set(name, fn)
      return name
    },
    removeHandleEvent(name) {
      events.delete(name)
    },
  }
  hook.mounted()
  return {
    hook,
    status,
    areas,
    timers,
    events,
    listeners,
    copies: () => copies,
    click: () =>
      kind === "sharing" ? hook.listener() : hook.copy({ preventDefault() {} }),
  }
}

for (const kind of ["sharing", "invitation"]) {
  for (const api of ["absent", "rejected"]) {
    test(`${kind} copies with the shared fallback when Clipboard API is ${api}`, async (t) => {
      const c = setup(t, kind, api, true)
      await c.click()
      assert.equal(c.copies(), 1)
      assert.equal(c.status.textContent, "copied")
      assert.equal(c.areas.length, 1)
      assert.equal(c.areas[0].value, "")
      assert.equal(c.areas[0].connected, false)
      c.hook.destroyed()
    })
  }
  test(`${kind} offers selectable manual recovery after denial and erases it on timeout patch disconnect and destroy`, async (t) => {
    const c = setup(t, kind, "rejected", false)
    let reject
    navigator.clipboard.writeText = () =>
      new Promise((_, fail) => {
        reject = fail
      })
    const pending = c.click()
    await new Promise((resolve) => setImmediate(resolve))
    c.hook.beforeUpdate()
    reject(Error("denied"))
    await pending
    assert.equal(c.copies(), 0)
    assert.equal(c.areas.length, 0)
    assert.equal(c.status.textContent, "")
    navigator.clipboard.writeText = async () => {
      throw Error("denied")
    }
    for (const clear of [
      "timeout",
      "beforeUpdate",
      "disconnected",
      "destroyed",
    ]) {
      await c.click()
      assert.equal(c.status.textContent, "manual recovery")
      const area = c.areas.at(-1)
      assert.equal(area.value === "synthetic-copy-secret", true)
      assert.equal(area.selected, true)
      assert.equal(area.connected, true)
      assert.equal(area.readonly, "")
      assert.equal(c.timers.size, 1)
      if (clear === "timeout") {
        const timer = [...c.timers.values()][0]
        assert.ok(timer.ms <= 15000)
        timer.fn()
      } else c.hook[clear]()
      assert.equal(area.value, "")
      assert.equal(area.connected, false)
      assert.equal(c.timers.size, 0)
    }
    assert.equal(c.listeners.size, 0)
  })
}
