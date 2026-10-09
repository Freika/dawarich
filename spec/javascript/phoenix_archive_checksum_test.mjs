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
