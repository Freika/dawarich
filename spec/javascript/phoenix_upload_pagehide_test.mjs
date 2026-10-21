import assert from "node:assert/strict"
import test from "node:test"
import { Direct } from "../../app-phoenix/assets/js/uploaders/direct.js"

const flush = () => new Promise((resolve) => setImmediate(resolve))

function harness(t) {
  const names = [
    "fetch",
    "document",
    "XMLHttpRequest",
    "addEventListener",
    "removeEventListener",
  ]
  const previous = Object.fromEntries(
    names.map((name) => [name, globalThis[name]]),
  )
  t.after(() => {
    viewError?.()
    for (const name of names) globalThis[name] = previous[name]
  })
  const listeners = new Map(),
    requests = [],
    progress = []
  let xhr,
    viewError,
    aborts = 0
  globalThis.addEventListener = (name, callback) =>
    listeners.set(name, callback)
  globalThis.removeEventListener = (name, callback) => {
    if (listeners.get(name) === callback) listeners.delete(name)
  }
  globalThis.document = {
    querySelector: () => ({ getAttribute: () => "synthetic-csrf" }),
  }
  globalThis.fetch = async (url, options) => {
    requests.push({ url, options })
    return {
      ok: true,
      json: async () => ({ url: "synthetic-target", headers: {} }),
    }
  }
  globalThis.XMLHttpRequest = class {
    constructor() {
      xhr = this
      this.upload = { addEventListener() {}, removeEventListener() {} }
    }
    open() {}
    send() {}
    setRequestHeader() {}
    abort() {
      aborts++
    }
  }
  Direct(
    [
      {
        meta: { upload_ref: "owned-reference" },
        file: new Blob(["synthetic"]),
        isCancelled: () => false,
        onCancel() {},
        progress: (value) => progress.push(value),
        error: () =>
          assert.fail("page departure must cancel without a late error"),
      },
    ],
    (callback) => {
      viewError = callback
    },
  )
  return {
    listeners,
    requests,
    progress,
    xhr: () => xhr,
    aborts: () => aborts,
    viewError: () => viewError(),
  }
}

test("pagehide cancels an in-flight disk PUT once with a keepalive owner reference", async (t) => {
  const h = harness(t)
  await flush()
  const lateCompletion = h.xhr().onload
  assert.equal(typeof h.listeners.get("pagehide"), "function")
  h.listeners.get("pagehide")()
  h.viewError()
  await flush()
  const cancelled = h.requests.filter((request) =>
    request.url.endsWith("/cancel"),
  )
  assert.equal(cancelled.length, 1)
  assert.equal(cancelled[0].options.keepalive, true)
  assert.deepEqual(JSON.parse(cancelled[0].options.body), {
    upload_ref: "owned-reference",
  })
  assert.equal(h.aborts(), 1)
  assert.equal(h.listeners.size, 0)
  lateCompletion()
  assert.deepEqual(h.progress, [])
})

test("completed disk PUT removes its departure listener before reporting completion", async (t) => {
  const h = harness(t)
  await flush()
  assert.equal(typeof h.listeners.get("pagehide"), "function")
  h.xhr().status = 204
  h.xhr().onload()
  assert.equal(h.listeners.size, 0)
  assert.deepEqual(h.progress, [100])
  assert.equal(
    h.requests.filter((request) => request.url.endsWith("/cancel")).length,
    0,
  )
})
