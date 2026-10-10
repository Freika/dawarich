import assert from "node:assert/strict"
import test from "node:test"

const { RichAttachments } = await import(
  "../../app-phoenix/assets/js/editor/attachments.js"
)

const file = (name = "photo.png") => ({ name, size: 9, type: "image/png" })

function attachment(f) {
  return {
    file: f,
    progress: [],
    attributes: null,
    removed: false,
    setUploadProgress(value) {
      this.progress.push(value)
    },
    setAttributes(attributes) {
      this.attributes = attributes
    },
    remove() {
      this.removed = true
    },
  }
}

function hook(replies = {}) {
  const pushed = []
  const status = { textContent: "" }
  return {
    alive: true,
    pushed,
    status,
    el: { dataset: { uploadFailed: "Upload failed" } },
    statusElement: () => status,
    pushEvent(name, payload, reply) {
      pushed.push([name, payload])
      const answer = replies[name]
      if (reply && answer)
        reply(typeof answer === "function" ? answer() : answer)
    },
  }
}

const reserve = { upload_ref: "ref-1", url: "/put", headers: { a: "b" } }
const claim = { sgid: "sgid-1", url: "/u", href: "/h" }
const digest = () => Promise.resolve("AELTPXGTbs81Ygn6v0o2PQ==")

function transport(outcome = Promise.resolve()) {
  const calls = []
  const fn = (url, headers, f, onProgress) => {
    calls.push({ url, headers, f, aborted: false })
    onProgress(40)
    const call = calls.at(-1)
    return {
      done: outcome,
      abort: () => {
        call.aborted = true
      },
    }
  }
  fn.calls = calls
  return fn
}

test("an upload reserves a target, sends the file, then attaches the claimed attachable", async () => {
  const h = hook({ rich_upload_reserve: reserve, rich_upload_claim: claim })
  const put = transport()
  const a = attachment(file())
  await new RichAttachments(h, { digest, transport: put }).add(a)

  assert.deepEqual(h.pushed[0], [
    "rich_upload_reserve",
    {
      name: "photo.png",
      size: 9,
      type: "image/png",
      checksum: "AELTPXGTbs81Ygn6v0o2PQ==",
    },
  ])
  assert.equal(put.calls[0].url, "/put")
  assert.deepEqual(h.pushed[1], ["rich_upload_claim", { upload_ref: "ref-1" }])
  assert.deepEqual(a.attributes, claim)
  assert.deepEqual(a.progress, [0, 40, 100])
})

test("cancelled or destroyed upload cannot insert an attachment", async () => {
  let finish
  const outcome = new Promise((resolve) => {
    finish = resolve
  })
  const h = hook({ rich_upload_reserve: reserve, rich_upload_claim: claim })
  const put = transport(outcome)
  const store = new RichAttachments(h, { digest, transport: put })
  const removed = attachment(file())
  const running = store.add(removed)
  await new Promise((resolve) => setImmediate(resolve))
  store.remove(removed)
  finish()
  await running
  assert.equal(removed.attributes, null)
  assert.equal(put.calls[0].aborted, true)
  assert.deepEqual(h.pushed.at(-1), [
    "rich_upload_cancel",
    { upload_ref: "ref-1" },
  ])

  store.transport = transport(new Promise(() => {}))
  const destroyed = attachment(file("second.png"))
  const second = store.add(destroyed)
  await new Promise((resolve) => setImmediate(resolve))
  store.cancelAll()
  await Promise.race([second, new Promise((resolve) => setImmediate(resolve))])
  assert.equal(destroyed.attributes, null)
  assert.equal(
    h.pushed.filter(([name]) => name === "rich_upload_claim").length,
    0,
  )
})

test("failed upload preserves text and can retry", async () => {
  const h = hook({ rich_upload_reserve: reserve, rich_upload_claim: claim })
  const failing = transport(Promise.reject(new Error("network")))
  const store = new RichAttachments(h, { digest, transport: failing })
  const first = attachment(file())
  await store.add(first)
  assert.equal(first.removed, true)
  assert.equal(first.attributes, null)
  assert.equal(h.status.textContent, "Upload failed")

  store.transport = transport()
  const again = attachment(file())
  await store.add(again)
  assert.equal(h.status.textContent, "")
  assert.deepEqual(again.attributes, claim)
})

test("a refused reservation or claim removes the pending attachment", async () => {
  const refused = hook({ rich_upload_reserve: { error: "refused" } })
  const a = attachment(file())
  await new RichAttachments(refused, { digest, transport: transport() }).add(a)
  assert.equal(a.removed, true)

  const foreign = hook({
    rich_upload_reserve: reserve,
    rich_upload_claim: { error: "refused" },
  })
  const b = attachment(file())
  await new RichAttachments(foreign, { digest, transport: transport() }).add(b)
  assert.equal(b.removed, true)
  assert.equal(b.attributes, null)
})

test("a failed upload releases its server reservation", async () => {
  const cancels = (h) =>
    h.pushed.filter(([name]) => name === "rich_upload_cancel")

  const putFailed = hook({ rich_upload_reserve: reserve })
  await new RichAttachments(putFailed, {
    digest,
    transport: transport(Promise.reject(new Error("network"))),
  }).add(attachment(file()))
  assert.deepEqual(cancels(putFailed), [
    ["rich_upload_cancel", { upload_ref: "ref-1" }],
  ])

  const claimRefused = hook({
    rich_upload_reserve: reserve,
    rich_upload_claim: { error: "refused" },
  })
  await new RichAttachments(claimRefused, {
    digest,
    transport: transport(),
  }).add(attachment(file()))
  assert.deepEqual(cancels(claimRefused), [
    ["rich_upload_cancel", { upload_ref: "ref-1" }],
  ])

  const reserveRefused = hook({ rich_upload_reserve: { error: "refused" } })
  await new RichAttachments(reserveRefused, {
    digest,
    transport: transport(),
  }).add(attachment(file()))
  assert.deepEqual(cancels(reserveRefused), [])
})

test("existing attachments without a file are left alone", async () => {
  const h = hook()
  await new RichAttachments(h, { digest }).add({ file: null })
  assert.deepEqual(h.pushed, [])
})
