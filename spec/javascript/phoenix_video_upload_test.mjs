import assert from "node:assert/strict"
import test from "node:test"
import { uploadRenderedVideo } from "../../app-phoenix/assets/js/video/upload.js"

function fakeXhr() {
  const created = []
  class FakeXhr {
    constructor() {
      this.listeners = {}
      this.upload = {
        listeners: {},
        addEventListener: (type, fn) => {
          this.upload.listeners[type] = fn
        },
        removeEventListener: (type, fn) => {
          if (this.upload.listeners[type] === fn)
            delete this.upload.listeners[type]
        },
      }
      this.headers = {}
      this.aborted = false
      created.push(this)
    }
    addEventListener(type, fn) {
      this.listeners[type] = fn
    }
    removeEventListener(type, fn) {
      if (this.listeners[type] === fn) delete this.listeners[type]
    }
    open(method, url) {
      this.method = method
      this.url = url
    }
    setRequestHeader(key, value) {
      this.headers[key] = value
    }
    send(body) {
      this.body = body
    }
    abort() {
      this.aborted = true
      this.listeners.abort?.()
    }
    finish(status) {
      this.status = status
      this.listeners.load?.()
    }
  }
  return { FakeXhr, created }
}

function server(overrides = {}) {
  const calls = []
  const replies = {
    "video:upload_target": {
      ok: true,
      url: "https://storage.example/put",
      headers: { "Content-Type": "video/mp4", "Content-MD5": "x" },
      reference: "signed-ref",
    },
    "video:save": { ok: true, id: 41 },
    "video:discard": { ok: true },
    ...overrides,
  }
  return {
    calls,
    request: async (event, payload) => {
      calls.push([event, payload])
      return replies[event]
    },
  }
}

const tick = () => new Promise((resolve) => setImmediate(resolve))
const blob = new Blob(["synthetic mp4 bytes"], { type: "video/mp4" })

async function started(overrides = {}) {
  const { FakeXhr, created } = fakeXhr()
  const remote = server(overrides.replies)
  const controller = new AbortController()
  const progress = []
  const uploading = uploadRenderedVideo({
    blob,
    name: "Leipzig loop",
    settings: { format: "square", watermark: false },
    request: remote.request,
    signal: controller.signal,
    onProgress: (ratio) => progress.push(ratio),
    XMLHttpRequest: FakeXhr,
    checksum: async () => "AELTPXGTbs81Ygn6v0o2PQ==",
  })
  while (created.length === 0 && remote.calls.length < 2) await tick()
  return { uploading, created, remote, controller, progress }
}

test("rendered video uploads to the reserved target then saves through the scope", async () => {
  const { uploading, created, remote, progress } = await started()
  const [xhr] = created
  assert.equal(xhr.method, "PUT")
  assert.equal(xhr.url, "https://storage.example/put")
  assert.equal(xhr.headers["Content-MD5"], "x")
  assert.equal(xhr.body.type, "video/mp4")
  assert.equal(xhr.body.name, "Leipzig loop.mp4")
  xhr.upload.listeners.progress({
    lengthComputable: true,
    loaded: 5,
    total: 10,
  })
  xhr.finish(204)
  assert.deepEqual(await uploading, { ok: true, id: 41 })
  assert.deepEqual(remote.calls, [
    [
      "video:upload_target",
      {
        byte_size: blob.size,
        checksum: "AELTPXGTbs81Ygn6v0o2PQ==",
        filename: "Leipzig loop.mp4",
      },
    ],
    [
      "video:save",
      {
        reference: "signed-ref",
        name: "Leipzig loop",
        settings: { format: "square", watermark: "false" },
      },
    ],
  ])
  assert.deepEqual(progress, [0.5])
  assert.deepEqual(xhr.listeners, {})
  assert.deepEqual(xhr.upload.listeners, {})
})

test("upload abort before commit discards the reservation and never saves", async () => {
  const { uploading, created, remote, controller } = await started()
  controller.abort()
  await assert.rejects(uploading, { name: "AbortError" })
  assert.equal(created[0].aborted, true)
  assert.deepEqual(
    remote.calls.map(([event]) => event),
    ["video:upload_target", "video:discard"],
  )
  assert.deepEqual(remote.calls[1][1], { reference: "signed-ref" })
  assert.deepEqual(created[0].listeners, {})
})

test("storage failure discards the reservation and reports the failure", async () => {
  const { uploading, created, remote } = await started()
  created[0].finish(500)
  await assert.rejects(uploading, { code: "upload_failed" })
  assert.deepEqual(
    remote.calls.map(([event]) => event),
    ["video:upload_target", "video:discard"],
  )
})

test("a refused upload target stops before any storage request", async () => {
  const { FakeXhr, created } = fakeXhr()
  const remote = server({
    "video:upload_target": { ok: false, error: "Ungültige Datei" },
  })
  await assert.rejects(
    uploadRenderedVideo({
      blob,
      name: "",
      settings: {},
      request: remote.request,
      XMLHttpRequest: FakeXhr,
      checksum: async () => "AELTPXGTbs81Ygn6v0o2PQ==",
    }),
    { message: "Ungültige Datei" },
  )
  assert.equal(created.length, 0)
  assert.deepEqual(remote.calls[0][1].filename, "route-video.mp4")
})

test("a committed save is not discarded by a late abort", async () => {
  let release
  const pendingSave = new Promise((resolve) => {
    release = resolve
  })
  const { FakeXhr, created } = fakeXhr()
  const calls = []
  const controller = new AbortController()
  const uploading = uploadRenderedVideo({
    blob,
    name: "Loop",
    settings: {},
    signal: controller.signal,
    XMLHttpRequest: FakeXhr,
    checksum: async () => "AELTPXGTbs81Ygn6v0o2PQ==",
    request: async (event) => {
      calls.push(event)
      if (event === "video:upload_target")
        return { ok: true, url: "/put", headers: {}, reference: "ref" }
      if (event === "video:save") return pendingSave
      return { ok: true }
    },
  })
  while (created.length === 0) await tick()
  created[0].finish(200)
  while (!calls.includes("video:save")) await tick()
  controller.abort()
  release({ ok: true, id: 7 })
  assert.deepEqual(await uploading, { ok: true, id: 7 })
  assert.deepEqual(calls, ["video:upload_target", "video:save"])
})

test("abort after storage completes but before save still discards", async () => {
  const { uploading, created, remote, controller } = await started()
  created[0].finish(201)
  controller.abort()
  await assert.rejects(uploading, { name: "AbortError" })
  assert.deepEqual(
    remote.calls.map(([event]) => event),
    ["video:upload_target", "video:discard"],
  )
})

test("abort during reservation discards the late target without starting a PUT", async () => {
  let release
  const pending = new Promise((resolve) => {
    release = resolve
  })
  const remote = server({ "video:upload_target": pending })
  const { FakeXhr, created } = fakeXhr()
  const controller = new AbortController()
  const uploading = uploadRenderedVideo({
    blob,
    request: remote.request,
    signal: controller.signal,
    XMLHttpRequest: FakeXhr,
    checksum: async () => "checksum",
  })
  const rejected = assert.rejects(uploading, { name: "AbortError" })
  await tick()
  controller.abort()
  release({ ok: true, url: "/put", reference: "late-ref" })
  await tick()
  assert.equal(created.length, 0)
  await rejected
  assert.deepEqual(
    remote.calls.map(([event]) => event),
    ["video:upload_target", "video:discard"],
  )
  assert.deepEqual(remote.calls[1][1], { reference: "late-ref" })
})

test("storage timeout discards the reservation, cleans listeners and permits retry", async () => {
  const { uploading, created, remote } = await started()
  assert.equal(created[0].timeout, 300_000)
  created[0].listeners.timeout()
  await assert.rejects(uploading, {
    code: "upload_timeout",
    message: "Video upload timed out; please retry",
  })
  assert.deepEqual(
    remote.calls.map(([event]) => event),
    ["video:upload_target", "video:discard"],
  )
  assert.deepEqual(created[0].listeners, {})
  assert.deepEqual(created[0].upload.listeners, {})
  const retry = await started()
  retry.created[0].finish(200)
  assert.deepEqual(await retry.uploading, { ok: true, id: 41 })
})
