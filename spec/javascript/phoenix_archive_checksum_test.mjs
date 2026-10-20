import assert from "node:assert/strict"
import test from "node:test"

const { base64Md5 } = await import(
  "../../app-phoenix/assets/js/hooks/archive_checksum.js"
)

test("the archive checksum matches Ruby's Digest::MD5.base64digest across chunks", async () => {
  const file = new Blob(["dawarich-archive-".repeat(20000)])
  const progress = []

  const checksum = await base64Md5(file, {
    chunkSize: 64 * 1024,
    onProgress: (percent) => progress.push(percent),
  })

  assert.equal(checksum, "AELTPXGTbs81Ygn6v0o2PQ==")
  assert.ok(progress.length > 1)
  assert.equal(progress.at(-1), 100)
})

test("the hook reports each selected file's checksum under its LiveView entry ref", async () => {
  const { ArchiveChecksum } = await import(
    "../../app-phoenix/assets/js/hooks/archive_checksum.js"
  )
  const listeners = {}
  const pushed = []
  const file = new Blob(["dawarich-archive-".repeat(20000)])
  file._phxRef = "7"

  const hook = Object.assign(Object.create(ArchiveChecksum), {
    el: {
      addEventListener: (name, fn) => {
        listeners[name] = fn
      },
      querySelector: () => null,
    },
    pushEvent: (event, payload) => pushed.push([event, payload]),
  })
  hook.mounted()

  listeners.change({ target: { type: "file", files: [file] } })
  await new Promise((resolve) => setTimeout(resolve, 50))

  assert.deepEqual(pushed, [
    ["archive_checksum", { ref: "7", checksum: "AELTPXGTbs81Ygn6v0o2PQ==" }],
  ])
})

test("lazy checksum refuses an aborted import before constructing the hasher", async () => {
  let release
  let loads = 0
  let constructed = 0
  const deferred = new Promise((resolve) => {
    release = resolve
  })
  const controller = new AbortController()
  const result = base64Md5(new Blob(["synthetic"]), {
    signal: controller.signal,
    loadMd5: () => {
      loads++
      return deferred
    },
  })
  assert.equal(loads, 1)
  controller.abort()
  release({
    default: {
      ArrayBuffer: class {
        constructor() {
          constructed++
        }
      },
    },
  })
  await assert.rejects(result, (error) => error.name === "AbortError")
  assert.equal(constructed, 0)
  assert.equal(
    await base64Md5(new Blob(["synthetic"])),
    "Xwa4XhYZsri1b3t1igoxCg==",
  )
})

test("component uploads send preparation events and files to their owning component", async () => {
  const { ArchiveChecksum } = await import("../../app-phoenix/assets/js/hooks/archive_checksum.js")
  const events = [], uploads = []
  const el = {
    dataset: { uploadKind: "imports", uploadName: "files", maxEntries: "1" },
    getAttribute: name => name === "phx-target" ? "7" : null,
    addEventListener() {},
    querySelector: () => null,
  }
  const hook = Object.assign(Object.create(ArchiveChecksum), {
    el,
    pushEvent: () => assert.fail("event escaped the upload component"),
    upload: () => assert.fail("files escaped the upload component"),
    pushEventTo: (target, name, payload) => events.push([target, name, payload]),
    uploadTo: (target, name, files) => uploads.push([target, name, files]),
  })
  hook.mounted()
  await hook.select([new File(["zip"], "sample.zip", { type: "application/zip" })])
  assert.equal(uploads.length, 1)
  assert.equal(uploads[0][0], el)
  assert.equal(uploads[0][1], "files")
  assert.equal(uploads[0][2][0].meta().checksum, "rc29eajYQXXCKbGSqtwC8g==")
  await hook.select([new File(["a"], "a.zip"), new File(["b"], "b.zip")])
  assert.deepEqual(events, [[el, "upload_selection_error", { kind: "too_many_files" }]])
})
