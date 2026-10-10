import assert from "node:assert/strict"
import test from "node:test"

const { Direct } = await import(
  "../../app-phoenix/assets/js/uploaders/direct.js"
)

function fakeXhr(t, status) {
  const sent = []
  class FakeXhr {
    constructor() {
      this.headers = {}
      this.upload = {
        listeners: {},
        addEventListener: (name, fn) => {
          this.upload.listeners[name] = fn
        },
      }
      sent.push(this)
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
      this.upload.listeners.progress?.({
        lengthComputable: true,
        loaded: 5,
        total: 10,
      })
      this.status = status
      this.onload()
    }
    abort() {
      this.aborted = true
    }
  }
  const original = globalThis.XMLHttpRequest
  globalThis.XMLHttpRequest = FakeXhr
  t.after(() => {
    globalThis.XMLHttpRequest = original
  })
  return sent
}

function entry() {
  const calls = { progress: [], errors: 0 }
  return {
    calls,
    file: "archive-bytes",
    meta: {
      url: "http://www.example.com/rails/active_storage/disk/token",
      headers: { "Content-Type": "application/zip" },
    },
    progress: (percent) => calls.progress.push(percent),
    error: () => {
      calls.errors += 1
    },
  }
}

test("the direct uploader PUTs the file with the presigned headers and reports progress", (t) => {
  const sent = fakeXhr(t, 204)
  const upload = entry()

  Direct([upload], () => {})

  assert.equal(sent.length, 1)
  assert.equal(sent[0].method, "PUT")
  assert.equal(sent[0].url, upload.meta.url)
  assert.deepEqual(sent[0].headers, { "Content-Type": "application/zip" })
  assert.equal(sent[0].body, "archive-bytes")
  assert.deepEqual(upload.calls.progress, [50, 100])
  assert.equal(upload.calls.errors, 0)
})

test("the direct uploader reports an error when storage refuses the file", (t) => {
  fakeXhr(t, 422)
  const upload = entry()

  Direct([upload], () => {})

  assert.equal(upload.calls.errors, 1)
  assert.deepEqual(upload.calls.progress, [50])
})
