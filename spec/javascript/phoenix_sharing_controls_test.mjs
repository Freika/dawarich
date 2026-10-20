import assert from "node:assert/strict"
import test from "node:test"
import {
  SharingDialog,
  SharingPhrase,
  SharingReveal,
} from "../../app-phoenix/assets/js/hooks/sharing_controls.js"

const tick = () => new Promise((resolve) => setImmediate(resolve))
function hook(definition, el) {
  const events = new Map()
  const removed = []
  const instance = {
    ...definition,
    el,
    events,
    removed,
    handleEvent(name, fn) {
      events.set(name, fn)
      return name
    },
    removeHandleEvent(name) {
      removed.push(name)
      events.delete(name)
    },
    pushEvent(name) {
      this.pushed = name
    },
  }
  instance.mounted()
  return instance
}
function button() {
  const listeners = new Map()
  return {
    disabled: false,
    listeners,
    addEventListener(name, fn) {
      listeners.set(name, fn)
    },
    removeEventListener(name) {
      listeners.delete(name)
    },
  }
}
function setup() {
  globalThis.document = {
    querySelector() {
      return { content: "synthetic-csrf" }
    },
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
}

test("copy permission failure is visible and reveals are erased on navigation", async () => {
  setup()
  const action = button(),
    status = { textContent: "" }
  const el = {
    dataset: {
      url: "/native/sharing/id/phrase",
      copiedLabel: "copied",
      failedLabel: "failed",
    },
    querySelector(selector) {
      return selector === "[data-reveal]" ? action : status
    },
  }
  globalThis.fetch = async () => ({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "ephemeral-phrase",
  })
  const instance = hook(SharingReveal, el)
  await instance.listener()
  assert.equal(status.textContent, "failed")
  assert.equal(action.disabled, false)
  assert.ok(!JSON.stringify(instance).includes("ephemeral-phrase"))
  let release,
    signal,
    writes = 0
  navigator.clipboard.writeText = async () => {
    writes++
  }
  globalThis.fetch = (_url, opts) => {
    signal = opts.signal
    return new Promise((resolve) => {
      release = resolve
    })
  }
  const pending = instance.listener()
  await tick()
  instance.beforeUpdate()
  assert.ok(signal.aborted)
  release({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "late-phrase",
  })
  await pending
  assert.equal(writes, 0)
  assert.equal(status.textContent, "")
  instance.destroyed()
  assert.equal(action.listeners.size, 0)
  assert.equal(instance.events.size, 0)
})

test("sharing confirmation Escape cancels the pending effect and teardown returns focus", () => {
  setup()
  const trigger = {
    isConnected: true,
    focus() {
      this.focused = true
    },
  }
  document.activeElement = trigger
  const el = {
    ...button(),
    open: false,
    showModal() {
      this.open = true
    },
    close() {
      this.open = false
    },
  }
  const instance = hook(SharingDialog, el)
  assert.ok(el.open)
  el.listeners.get("cancel")({ preventDefault() {} })
  assert.equal(instance.pushed, "sharing_cancel")
  assert.equal(el.open, false)
  instance.destroyed()
  assert.equal(el.listeners.size, 0)
  assert.ok(trigger.focused)
})

test("generated phrases stay in transient input DOM and failed submissions or disconnect erase them", async () => {
  setup()
  let release, signal
  globalThis.fetch = (_url, opts) => {
    signal = opts.signal
    return new Promise((resolve) => {
      release = resolve
    })
  }
  const el = {
    ...button(),
    value: "",
    dataset: { url: "/native/sharing/phrase" },
  }
  const instance = hook(SharingPhrase, el)
  await tick()
  release({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "fresh-phrase",
  })
  await tick()
  assert.equal(el.value, "fresh-phrase")
  assert.ok(!JSON.stringify({ ...instance, el: null }).includes("fresh-phrase"))
  instance.events.get("sharing-clear")({})
  assert.equal(el.value, "")
  el.value = "submitted-phrase"
  instance.disconnected()
  assert.equal(el.value, "")
  assert.ok(signal.aborted)
  instance.destroyed()
  assert.equal(instance.events.size, 0)
  const second = hook(SharingPhrase, {
    ...button(),
    value: "",
    dataset: { url: "/native/sharing/phrase" },
  })
  await tick()
  second.beforeUpdate()
  release({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "late-generated-phrase",
  })
  await tick()
  assert.equal(second.el.value, "")
  second.destroyed()
})

test("editing the phrase cancels a pending generator without erasing the user's choice", async () => {
  setup()
  let release, signal
  globalThis.fetch = (_url, options) => {
    signal = options.signal
    return new Promise((resolve) => {
      release = resolve
    })
  }
  const el = {
    ...button(),
    value: "",
    dataset: { url: "/native/sharing/phrase" },
  }
  const instance = hook(SharingPhrase, el)
  const input = el.listeners.get("input")
  assert.equal(typeof input, "function")
  el.value = "owner-chosen-phrase"
  input()
  assert.ok(signal.aborted)
  release({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "late-generated-phrase",
  })
  await tick()
  assert.equal(el.value, "owner-chosen-phrase")
  instance.destroyed()
  assert.equal(el.value, "")
  assert.equal(el.listeners.size, 0)
})

test("sharing reveal fields select locally and erase private values at every boundary", async () => {
  setup()
  navigator.clipboard.writeText = async () => {}
  globalThis.fetch = async () => ({
    ok: true,
    redirected: false,
    headers: { get: () => "text/plain" },
    text: async () => "transient-fixture-phrase",
  })
  for (const privateValue of [true, false]) {
    const action = button(),
      status = { textContent: "" },
      field = button()
    Object.assign(field, {
      tagName: "INPUT",
      value: privateValue ? "" : "https://www.example.com/s/fixture",
      hasAttribute: (name) => name === "data-private-reveal" && privateValue,
      select() {
        this.selected = (this.selected || 0) + 1
      },
    })
    const initial = field.value
    const el = {
      dataset: {
        url: "/native/sharing/id/phrase",
        copiedLabel: "copied",
        failedLabel: "failed",
      },
      querySelector(selector) {
        return selector === "[data-reveal]"
          ? action
          : selector === "[data-status]"
            ? status
            : field
      },
    }
    const instance = hook(SharingReveal, el)
    await instance.listener()
    assert.equal(
      field.value,
      privateValue ? "transient-fixture-phrase" : initial,
    )
    field.listeners.get("click")()
    assert.equal(field.selected, 1)
    instance.beforeUpdate()
    assert.equal(field.value, privateValue ? "" : initial)
    await instance.listener()
    instance.disconnected()
    assert.equal(field.value, privateValue ? "" : initial)
    await instance.listener()
    instance.destroyed()
    assert.equal(field.value, privateValue ? "" : initial)
    assert.equal(field.listeners.size, 0)
    assert.ok(!Object.values(instance).includes("transient-fixture-phrase"))
  }
})

for (const kind of ["month", "digest", "achievements"]) {
  test(`report ${kind} copy stays local and resolves its complete public URL`, async (t) => {
    setup()
    const previous = Object.getOwnPropertyDescriptor(globalThis, "window")
    t.after(() =>
      previous
        ? Object.defineProperty(globalThis, "window", previous)
        : delete globalThis.window,
    )
    globalThis.window = {
      isSecureContext: true,
      location: { origin: "https://dawarich.example" },
    }
    const writes = [],
      action = button(),
      status = { textContent: "" },
      field = button()
    Object.assign(field, {
      tagName: "INPUT",
      value: `/shared/${kind}/fixture`,
      hasAttribute: () => false,
      select() {
        this.selected = true
      },
    })
    navigator.clipboard.writeText = async (value) => writes.push(value)
    globalThis.fetch = async () => {
      throw Error("unexpected report request")
    }
    const instance = hook(SharingReveal, {
      dataset: {
        nativePublicUrl: field.value,
        copiedLabel: "copied",
        failedLabel: "failed",
      },
      querySelector(selector) {
        return selector === "[data-reveal]"
          ? action
          : selector === "[data-status]"
            ? status
            : field
      },
    })
    await instance.listener()
    assert.deepEqual(writes, [
      `https://dawarich.example/shared/${kind}/fixture`,
    ])
    field.listeners.get("click")()
    assert.equal(field.selected, true)
    instance.destroyed()
    assert.equal(field.listeners.size, 0)
    assert.equal(field.value, `/shared/${kind}/fixture`)
  })
}
