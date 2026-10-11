import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const stripImports = (source) =>
  source
    .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
    .replace(/^import "[^"]+"\n/gm, "")
class Hub {
  constructor() {
    this.listeners = new Map()
  }
  addEventListener(type, callback) {
    const set = this.listeners.get(type) ?? new Set()
    set.add(callback)
    this.listeners.set(type, set)
  }
  removeEventListener(type, callback) {
    this.listeners.get(type)?.delete(callback)
  }
  dispatchEvent(event) {
    return Promise.all(
      [...(this.listeners.get(event.type) ?? [])].map((callback) =>
        callback(event),
      ),
    )
  }
  count() {
    return [...this.listeners.values()].reduce((n, set) => n + set.size, 0)
  }
}
test("R06: studio recipe and native hooks matches current Rails contract without a native-owner Rails effect", async () => {
  const uploads = [],
    posted = [],
    progress = []
  const xhr = {
    upload: new Hub(),
    aborts: 0,
    abort() {
      this.aborts++
    },
  }
  const globals = {
    console,
    FormData,
    File,
    AbortController,
    DOMException,
    document: {
      querySelector() {
        return { content: "synthetic-csrf" }
      },
    },
    DirectUpload: class {
      constructor(file, url, delegate) {
        uploads.push({ file, url })
        this.delegate = delegate
      }
      create(callback) {
        this.delegate.directUploadWillStoreFileWithXHR(xhr)
        xhr.upload.dispatchEvent({
          type: "progress",
          lengthComputable: true,
          loaded: 1,
          total: 2,
        })
        callback(null, { signed_id: "synthetic-signed-id" })
      }
    },
    async fetch(url, request) {
      posted.push({ url, request })
      return {
        ok: true,
        text: async () =>
          '<turbo-stream action="prepend" target="route-video-gallery-list"></turbo-stream>',
      }
    },
  }
  const context = vm.createContext(globals)
  const code = await readFile(
    new URL(
      "../../../app/javascript/video_studio/save_video.js",
      import.meta.url,
    ),
    "utf8",
  )
  vm.runInContext(
    stripImports(code).replace(/export /g, "") +
      "\nglobalThis.saveAPI = saveVideo",
    context,
  )
  const signal = new AbortController().signal
  const recipe = {
    source: "map",
    start_at: "2026-10-03T08:00:00Z",
    end_at: "2026-10-03T09:00:00Z",
    track_color: "#aa33cc",
    fog_opacity: 65,
    show_route: false,
  }
  const stream = await globals.saveAPI({
    blob: new Blob(["synthetic-mp4"]),
    name: "Route",
    settings: recipe,
    uploadUrl: "/rails/active_storage/direct_uploads",
    createUrl: "/route_videos",
    signal,
    onProgress: (ratio) => progress.push(ratio),
  })
  assert.equal(
    posted[0].request.body.get("route_video[settings][end_at]"),
    recipe.end_at,
  )
  assert.equal(
    posted[0].request.body.get("route_video[settings][start_at]"),
    recipe.start_at,
  )
  assert.equal(
    posted[0].request.body.get("route_video[settings][show_route]"),
    "false",
  )
  assert.equal(
    posted[0].request.body.get("route_video[file]"),
    "synthetic-signed-id",
  )
  assert.equal(posted[0].request.headers["X-CSRF-Token"], "synthetic-csrf")
  assert.equal(
    posted[0].request.signal,
    signal,
    "save carries the studio abort signal",
  )
  assert.deepEqual(progress, [0.5])
  assert.equal(
    xhr.upload.count(),
    0,
    "upload progress listener is detached after completion",
  )
  assert.ok(stream.includes("turbo-stream"))
  const aborted = new AbortController()
  aborted.abort()
  await assert.rejects(
    globals.saveAPI({
      blob: new Blob(["synthetic"]),
      name: "Route",
      settings: recipe,
      signal: aborted.signal,
    }),
    /abort|cancel/i,
  )
  assert.equal(posted.length, 1)
  let uploadComplete
  globals.DirectUpload = class {
    constructor(_file, _url, delegate) {
      this.delegate = delegate
    }
    create(callback) {
      this.delegate.directUploadWillStoreFileWithXHR(xhr)
      uploadComplete = callback
    }
  }
  const cancelled = new AbortController()
  const inFlight = globals.saveAPI({
    blob: new Blob(["synthetic"]),
    name: "Route",
    settings: recipe,
    signal: cancelled.signal,
  })
  cancelled.abort()
  await assert.rejects(inFlight, /cancel/i)
  uploadComplete(null, { signed_id: "late-synthetic-upload" })
  assert.equal(
    posted.length,
    1,
    "cancelled uploads cannot save after their late callback",
  )
  assert.equal(xhr.upload.count(), 0)
  assert.equal(xhr.aborts, 1)
})
