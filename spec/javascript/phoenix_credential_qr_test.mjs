import assert from "node:assert/strict"
import test from "node:test"
import { CredentialQr } from "../../app-phoenix/assets/js/hooks/credential_qr.js"

test("QR reveals clear on patch disconnect close and destroy and reject stale responses", async (t) => {
  const originals = ["fetch", "document", "DOMParser"].map((key) => [key, globalThis[key]])
  t.after(() => { for (const [key, value] of originals) globalThis[key] = value })
  const listeners = new Map()
  const dialogListeners = new Map()
  const requests = []
  const dialog = {
    addEventListener: (key, handler) => dialogListeners.set(key, handler),
    removeEventListener: (key) => dialogListeners.delete(key),
  }
  const el = {
    children: [],
    replaceChildren(...children) { this.children = children },
    addEventListener: (key, handler) => listeners.set(key, handler),
    removeEventListener: (key) => listeners.delete(key),
    closest: () => dialog,
  }
  globalThis.document = { querySelector: () => ({ content: "synthetic-csrf" }), importNode: (value) => value }
  globalThis.DOMParser = class { parseFromString() { return { documentElement: { localName: "svg" } } } }
  globalThis.fetch = (path, options) => new Promise((resolve) => requests.push({ path, options, resolve }))
  const hook = Object.assign(Object.create(CredentialQr), { el })
  hook.mounted()
  for (const clear of [() => hook.beforeUpdate(), () => hook.disconnected(), () => dialogListeners.get("close")()]) {
    const pending = hook.reveal()
    const request = requests.at(-1)
    assert.equal(request.path, "/native/account/qr")
    assert.equal(request.options.cache, "no-store")
    assert.equal(request.options.credentials, "same-origin")
    clear()
    assert.equal(request.options.signal.aborted, true)
    request.resolve({ ok: true, text: async () => "<svg/>" })
    await pending
    assert.equal(el.children.length, 0)
  }
  const pending = hook.reveal()
  requests.at(-1).resolve({ ok: true, text: async () => "<svg/>" })
  await pending
  assert.equal(el.children.length, 1)
  hook.destroyed()
  assert.equal(el.children.length, 0)
  assert.equal(listeners.size, 0)
  assert.equal(dialogListeners.size, 0)
})
