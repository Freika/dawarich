import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/trip_maplibre_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { default: TripController } = await import(
  `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
)

function fixture(t, ready) {
  const requests = []
  const visits = []
  const warnings = []
  const originals = new Map()
  function install(name, value) {
    if (!originals.has(name)) {
      originals.set(name, Object.getOwnPropertyDescriptor(globalThis, name))
    }
    Object.defineProperty(globalThis, name, {
      configurable: true,
      writable: true,
      value,
    })
  }
  t.after(() => {
    for (const [name, original] of originals) {
      if (original) Object.defineProperty(globalThis, name, original)
      else delete globalThis[name]
    }
  })
  install("window", { location: { href: "http://localhost/trips/1" } })
  install("Turbo", { visit: (...args) => visits.push(args) })
  install(
    "DOMParser",
    class {
      parseFromString(html, type) {
        assert.equal(html, "latest HTML")
        assert.equal(type, "text/html")
        return {
          querySelector(selector) {
            assert.equal(selector, '[data-trip-maplibre-target="map"]')
            return ready ? {} : null
          },
        }
      }
    },
  )
  install("fetch", async (...args) => {
    requests.push(args)
    return { ok: true, text: async () => "latest HTML" }
  })
  t.mock.method(console, "warn", (...args) => warnings.push(args))
  const controller = new TripController()
  controller.element = { isConnected: true }
  controller.hasPathPendingTarget = true
  return { controller, requests, visits, warnings, install }
}

test("a ready path replaces the current page through Turbo", async (t) => {
  const { controller, requests, visits } = fixture(t, true)

  await controller.syncPendingPath()

  assert.deepEqual(requests, [
    [
      window.location.href,
      { headers: { Accept: "text/html" }, credentials: "same-origin" },
    ],
  ])
  assert.deepEqual(visits, [[window.location.href, { action: "replace" }]])
})

test("a path still being calculated does not reload the page", async (t) => {
  const { controller, requests, visits } = fixture(t, false)

  await controller.syncPendingPath()

  assert.equal(requests.length, 1)
  assert.equal(visits.length, 0)
})

test("a fetch error warns and allows a later sync to recover", async (t) => {
  const { controller, visits, warnings, install } = fixture(t, true)
  const successfulFetch = globalThis.fetch
  const error = new Error("Connection failed")
  install("fetch", async () => {
    throw error
  })

  await controller.syncPendingPath()

  assert.deepEqual(warnings, [["Could not synchronize trip path", error]])
  assert.equal(visits.length, 0)
  install("fetch", successfulFetch)
  await controller.syncPendingPath()
  assert.equal(visits.length, 1)
})

test("a sync requested during a stale fetch runs again afterwards", async (t) => {
  const { controller, requests, visits, install } = fixture(t, true)
  let release
  const responses = [
    new Promise((resolve) => {
      release = resolve
    }),
  ]
  install("fetch", async (...args) => {
    requests.push(args)
    return responses.shift() || { ok: true, text: async () => "latest HTML" }
  })

  const first = controller.syncPendingPath()
  await controller.syncPendingPath()
  release({ ok: false, status: 503 })
  await first
  await new Promise((resolve) => setImmediate(resolve))

  assert.equal(requests.length, 2)
  assert.deepEqual(visits, [[window.location.href, { action: "replace" }]])
})
