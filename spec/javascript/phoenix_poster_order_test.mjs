import assert from "node:assert/strict"
import { test } from "node:test"
import { submitPrintOrder } from "../../app-phoenix/assets/js/poster/order.js"
import { bindOrderControls } from "../../app-phoenix/assets/js/poster/order_controls.js"
import { bindStudioSwitch } from "../../app-phoenix/assets/js/poster/switch.js"

const errors = {
  too_large:
    "The exported PDF is too large (50 MB max). Lower the DPI cap or zoom out.",
  generic: "Order upload failed — try again.",
  connection: "Could not reach the order service — check your connection.",
}

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 0))

class FakeXhr {
  static instances = []

  constructor() {
    FakeXhr.instances.push(this)
    this.listeners = {}
    this.uploadListeners = {}
    this.responseType = ""
    this.aborted = false
    this.upload = {
      addEventListener: (type, handler) => {
        this.uploadListeners[type] = handler
      },
      removeEventListener: (type, handler) => {
        if (this.uploadListeners[type] === handler)
          delete this.uploadListeners[type]
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

  removeEventListener(type, handler) {
    if (this.listeners[type] === handler) delete this.listeners[type]
  }

  send(body) {
    this.body = body
  }

  abort() {
    this.aborted = true
  }

  respond(status, response) {
    this.status = status
    this.response = response
    this.listeners.load?.()
  }

  failNetwork() {
    this.listeners.error?.()
  }

  emitUploadProgress(loaded, total) {
    this.uploadListeners.progress?.({ lengthComputable: true, loaded, total })
  }
}

function manualTimers() {
  const pending = []
  return {
    pending,
    setTimeout: (callback, delay) => {
      pending.push({ callback, delay, cleared: false })
      return pending.length - 1
    },
    clearTimeout: (id) => {
      if (pending[id]) pending[id].cleared = true
    },
  }
}

const orderParams = (overrides = {}) => ({
  url: "https://prints.example.com/api/orders",
  blob: new Blob(["%PDF-fake"], { type: "application/pdf" }),
  sku: "print-30x40",
  title: "Berlin",
  themeBase: "blueprint",
  layoutId: "print-30x40",
  errors,
  XMLHttpRequest: FakeXhr,
  timers: manualTimers(),
  ...overrides,
})

const withFakeXhr = async (run) => {
  FakeXhr.instances = []
  await run()
}

test("posts the order form and resolves token + checkout url", () =>
  withFakeXhr(async () => {
    const promise = submitPrintOrder(orderParams())
    const xhr = FakeXhr.instances[0]

    assert.equal(xhr.method, "POST")
    assert.equal(xhr.url, "https://prints.example.com/api/orders")
    assert.equal(xhr.responseType, "json")
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
    const promise = submitPrintOrder(
      orderParams({ onProgress: (fraction) => fractions.push(fraction) }),
    )
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

test("cancelled print upload closes XHR listeners and never enables checkout", () =>
  withFakeXhr(async () => {
    const controller = new AbortController()
    const timers = manualTimers()
    const promise = submitPrintOrder(
      orderParams({ signal: controller.signal, timers, onProgress: () => {} }),
    )
    const xhr = FakeXhr.instances[0]
    controller.abort()
    await assert.rejects(promise, { name: "AbortError" })
    assert.equal(xhr.aborted, true)
    assert.deepEqual(Object.keys(xhr.listeners), [])
    assert.deepEqual(Object.keys(xhr.uploadListeners), [])
    assert.ok(timers.pending.every((timer) => timer.cleared))

    const preAborted = new AbortController()
    preAborted.abort()
    await assert.rejects(
      submitPrintOrder(orderParams({ signal: preAborted.signal })),
      { name: "AbortError" },
    )
    assert.equal(FakeXhr.instances.length, 1)

    const stalledTimers = manualTimers()
    const stalled = submitPrintOrder(
      orderParams({ timers: stalledTimers, timeoutMs: 1000 }),
    )
    assert.equal(stalledTimers.pending[0].delay, 1000)
    stalledTimers.pending[0].callback()
    await assert.rejects(stalled, /Could not reach the order service/)
    assert.equal(FakeXhr.instances[1].aborted, true)
  }))

function element(props = {}) {
  const target = new EventTarget()
  const classes = new Set(props.classes ?? [])
  const attributes = new Map(Object.entries(props.attributes ?? {}))
  return Object.assign(target, {
    dataset: {},
    value: "",
    disabled: false,
    hidden: false,
    textContent: "",
    classList: {
      toggle: (name, on) => (on ? classes.add(name) : classes.delete(name)),
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
    },
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: (name) => attributes.delete(name),
    getAttribute: (name) => attributes.get(name) ?? null,
    ...props,
  })
}

function step(name) {
  const parts = {
    spinner: element({ classes: ["hidden"] }),
    done: element({ classes: ["hidden"] }),
    bar: element({ classes: ["hidden"] }),
  }
  return element({
    dataset: { posterOrderStep: name },
    classes: ["opacity-40"],
    parts,
    querySelector: (selector) => parts[/data-role='(\w+)'/.exec(selector)[1]],
  })
}

function orderRoot() {
  const nodes = {
    layout: element({ value: "print-a3" }),
    download: element(),
    "order-section": element({ classes: ["hidden"] }),
    "order-cta": element(),
    "order-open": element(),
    "size-picker": element({ classes: ["hidden"] }),
    "size-cancel": element(),
    "order-dialog": element({ classes: ["hidden"] }),
    "order-summary": element(),
    "order-error": element({ classes: ["hidden"] }),
    "order-actions": element(),
    "order-confirm": element(),
    "order-back": element(),
    "order-steps": element({ classes: ["hidden"] }),
    "upload-bar": element(),
    checkout: element({
      classes: ["btn-disabled"],
      attributes: { "aria-disabled": "true" },
    }),
    "order-page": element({ classes: ["hidden"] }),
    "order-done": element({ classes: ["hidden"] }),
  }
  const steps = ["prepare", "upload", "checkout"].map(step)
  const sizes = ["print-30x40", "print-50x70", "print-70x100"].map((id) => {
    const price = element()
    return element({
      dataset: { posterPrintSize: id },
      price,
      querySelector: () => price,
    })
  })
  return {
    nodes,
    steps,
    sizes,
    querySelector: (selector) =>
      nodes[/^\[data-poster-([a-z-]+)\]$/.exec(selector)?.[1]] ?? null,
    querySelectorAll: (selector) =>
      ({
        "[data-poster-order-step]": steps,
        "[data-poster-print-size]": sizes,
      })[selector] ?? [],
  }
}

const labels = {
  "print-a3": "A3 Portrait",
  "print-30x40": "30 × 40 cm",
  "print-50x70": "50 × 70 cm",
}

function orderStudio(layoutId = "print-a3") {
  const studio = {
    state: { layoutId, title: " Berlin ", themeKey: "noir" },
    exportRequest: () => ({
      layout: { id: studio.state.layoutId },
      title: "Berlin",
    }),
    update(patch) {
      studio.state = { ...studio.state, ...patch }
    },
  }
  return studio
}

function bindOrder({ root, studio, submit, exports }) {
  const removers = []
  const on = (target, type, handler) => {
    target.addEventListener(type, handler)
    removers.push(() => target.removeEventListener(type, handler))
  }
  on(root.nodes.layout, "change", () =>
    studio.update({ layoutId: root.nodes.layout.value }),
  )
  const order = bindOrderControls({
    root,
    find: (name) => root.querySelector(`[data-poster-${name}]`),
    on,
    studio,
    exports,
    strings: {
      order_summary: "%{layout} poster — %{price}",
      "order_errors.generic": errors.generic,
    },
    printOrderUrl: "https://prints.example.com/api/orders",
    loadLibrary: async () => ({}),
    maxDimensionPx: 8192,
    submit,
    layoutLabel: (id) => labels[id],
  })
  return {
    order,
    unbind: () => {
      for (const remove of removers) remove()
    },
  }
}

const doneExports = (requests = []) => ({
  busy: false,
  run: async (request, options) => {
    requests.push([request, options])
    return { status: "done", blob: new Blob(["%PDF"]) }
  },
  cancel() {},
})

test("layout requiring size picker preserves selected product", async () => {
  const root = orderRoot()
  const studio = orderStudio()
  const { unbind } = bindOrder({
    root,
    studio,
    submit: async () => ({}),
    exports: doneExports(),
  })
  assert.equal(root.nodes["order-section"].classList.contains("hidden"), false)
  assert.deepEqual(
    root.sizes.map((size) => size.price.textContent),
    ["€44.99", "€54.99", "€74.99"],
  )
  root.nodes["order-open"].dispatchEvent(new Event("click"))
  assert.equal(root.nodes["size-picker"].classList.contains("hidden"), false)
  assert.equal(root.nodes["order-dialog"].classList.contains("hidden"), true)
  assert.equal(root.nodes["order-cta"].classList.contains("hidden"), true)

  root.sizes[1].dispatchEvent(new Event("click"))
  assert.equal(root.nodes.layout.value, "print-50x70")
  assert.equal(studio.state.layoutId, "print-50x70")
  assert.equal(root.nodes["order-dialog"].classList.contains("hidden"), false)
  assert.equal(root.nodes["size-picker"].classList.contains("hidden"), true)
  assert.equal(
    root.nodes["order-summary"].textContent,
    "50 × 70 cm poster — €54.99",
  )

  root.nodes.layout.value = "print-a3"
  root.nodes.layout.dispatchEvent(new Event("change"))
  assert.equal(root.nodes["size-picker"].classList.contains("hidden"), false)
  root.nodes["size-cancel"].dispatchEvent(new Event("click"))
  assert.equal(root.nodes["order-cta"].classList.contains("hidden"), false)
  unbind()
})

test("checkout only becomes enabled for current successful order", async () => {
  const root = orderRoot()
  const studio = orderStudio("print-30x40")
  const uploads = []
  const requests = []
  const submit = (params) => {
    const pending = deferred()
    uploads.push({ params, pending })
    return pending.promise
  }
  const { order, unbind } = bindOrder({
    root,
    studio,
    submit,
    exports: doneExports(requests),
  })
  root.nodes["order-open"].dispatchEvent(new Event("click"))
  assert.equal(
    root.nodes["order-summary"].textContent,
    "30 × 40 cm poster — €44.99",
  )
  root.nodes["order-confirm"].dispatchEvent(new Event("click"))
  await tick()
  assert.deepEqual(requests[0][1], { deliver: false })
  assert.equal(requests[0][0].dpi, 300)
  assert.equal(requests[0][0].format, "pdf")
  assert.equal(uploads[0].params.sku, "poster-30x40")
  assert.equal(uploads[0].params.title, "Berlin")
  assert.equal(uploads[0].params.themeBase, "noir")
  assert.equal(root.nodes.download.disabled, true)
  uploads[0].params.onProgress(0.42)
  assert.equal(root.nodes["upload-bar"].value, 42)

  order.cancel()
  assert.equal(uploads[0].params.signal.aborted, true)
  root.nodes["order-confirm"].dispatchEvent(new Event("click"))
  await tick()
  uploads[0].pending.resolve({
    token: "stale",
    checkoutUrl: "https://pay.example/stale",
  })
  await tick()
  assert.equal(root.nodes.checkout.href, undefined)
  assert.equal(root.nodes.checkout.classList.contains("btn-disabled"), true)

  uploads[1].pending.resolve({
    token: "tok",
    checkoutUrl: "https://pay.example/current",
  })
  await tick()
  assert.equal(root.nodes.checkout.href, "https://pay.example/current")
  assert.equal(root.nodes.checkout.classList.contains("btn-disabled"), false)
  assert.equal(root.nodes.checkout.getAttribute("aria-disabled"), null)
  assert.equal(
    root.nodes["order-page"].href,
    "https://prints.example.com/orders/tok",
  )
  assert.equal(root.nodes["order-page"].classList.contains("hidden"), false)
  assert.equal(root.nodes["order-done"].classList.contains("hidden"), false)
  assert.equal(root.nodes.download.disabled, false)

  root.nodes["order-confirm"].dispatchEvent(new Event("click"))
  await tick()
  uploads[2].pending.reject(new Error("Order upload failed — try again."))
  await tick()
  assert.equal(
    root.nodes["order-error"].textContent,
    "Order upload failed — try again.",
  )
  assert.equal(root.nodes["order-error"].classList.contains("hidden"), false)
  assert.equal(root.nodes["order-steps"].classList.contains("hidden"), true)
  assert.equal(root.nodes["order-actions"].classList.contains("hidden"), false)
  unbind()
})

test("switch to video carries the explicit trip-locked source and is refused during reload", () => {
  const button = element()
  const calls = []
  const studio = { state: { rangeLoading: true } }
  const source = { fixedRange: true }
  const removers = []
  bindStudioSwitch({
    find: () => button,
    on: (target, type, handler) => {
      target.addEventListener(type, handler)
      removers.push(() => target.removeEventListener(type, handler))
    },
    studio,
    source,
    openVideo: (value) => calls.push(["video", value]),
    close: () => calls.push(["close"]),
  })
  assert.equal(button.hidden, false)
  button.dispatchEvent(new Event("click"))
  assert.deepEqual(calls, [])
  studio.state = { rangeLoading: false }
  button.dispatchEvent(new Event("click"))
  assert.deepEqual(calls, [["close"], ["video", source]])
  for (const remove of removers) remove()

  const hidden = element()
  bindStudioSwitch({
    find: () => hidden,
    on: () => {},
    studio,
    source,
    close: () => {},
  })
  assert.equal(hidden.hidden, true)
})
