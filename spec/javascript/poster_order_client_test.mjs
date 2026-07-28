import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/poster_studio/ui/order_client.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { submitPrintOrder } = await import(moduleUrl)

class FakeXhr {
  static instances = []

  constructor() {
    FakeXhr.instances.push(this)
    this.listeners = {}
    this.uploadListeners = {}
    this.responseType = ""
    this.upload = {
      addEventListener: (type, handler) => {
        this.uploadListeners[type] = handler
      },
    }
  }

  open(method, url) {
    this.method = method
    this.url = url
  }

  addEventListener(type, handler) {
    this.listeners[type] = handler
  }

  send(body) {
    this.body = body
  }

  respond(status, response) {
    this.status = status
    this.response = response
    this.listeners.load()
  }

  failNetwork() {
    this.listeners.error()
  }

  emitUploadProgress(loaded, total) {
    this.uploadListeners.progress?.({ lengthComputable: true, loaded, total })
  }
}

function withFakeXhr(run) {
  FakeXhr.instances = []
  globalThis.XMLHttpRequest = FakeXhr
  return run().finally(() => {
    delete globalThis.XMLHttpRequest
  })
}

const orderParams = () => ({
  url: "https://prints.example.com/api/orders",
  blob: new Blob(["%PDF-fake"], { type: "application/pdf" }),
  sku: "print-30x40",
  title: "Berlin",
  themeBase: "blueprint",
  layoutId: "print-30x40",
})

test("posts the order form and resolves token + checkout url", () =>
  withFakeXhr(async () => {
    const promise = submitPrintOrder(orderParams())
    const xhr = FakeXhr.instances[0]

    assert.equal(xhr.method, "POST")
    assert.equal(xhr.url, "https://prints.example.com/api/orders")
    assert.ok(xhr.body instanceof FormData)
    assert.equal(xhr.body.get("sku"), "print-30x40")
    assert.equal(xhr.body.get("title"), "Berlin")
    assert.equal(xhr.body.get("theme_base"), "blueprint")
    assert.equal(xhr.body.get("layout_id"), "print-30x40")
    assert.equal(xhr.body.get("file").name, "poster.pdf")

    xhr.respond(201, {
      token: "tok123",
      checkout_url: "https://stripe.example.com/session",
    })
    assert.deepEqual(await promise, {
      token: "tok123",
      checkoutUrl: "https://stripe.example.com/session",
    })
  }))

test("reports upload progress fractions", () =>
  withFakeXhr(async () => {
    const fractions = []
    const promise = submitPrintOrder({
      ...orderParams(),
      onProgress: (fraction) => fractions.push(fraction),
    })
    const xhr = FakeXhr.instances[0]

    xhr.emitUploadProgress(5, 10)
    xhr.emitUploadProgress(10, 10)
    xhr.respond(201, { token: "t", checkout_url: "u" })
    await promise

    assert.deepEqual(fractions, [0.5, 1])
  }))

test("maps known error codes to friendly messages", () =>
  withFakeXhr(async () => {
    const promise = submitPrintOrder(orderParams())
    FakeXhr.instances[0].respond(422, { error: "too_large" })

    await assert.rejects(promise, /50 MB max/)
  }))

test("falls back to a generic message for unknown errors", () =>
  withFakeXhr(async () => {
    const promise = submitPrintOrder(orderParams())
    FakeXhr.instances[0].respond(500, null)

    await assert.rejects(promise, /Order upload failed/)
  }))

test("rejects with a connection message on network failure", () =>
  withFakeXhr(async () => {
    const promise = submitPrintOrder(orderParams())
    FakeXhr.instances[0].failNetwork()

    await assert.rejects(promise, /Could not reach the order service/)
  }))
