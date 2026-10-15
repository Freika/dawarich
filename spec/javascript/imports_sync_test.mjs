import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/imports_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(
  'import BaseController from "./base_controller"',
  "class BaseController {}",
)
const { default: ImportsController } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function fixture(t, statuses, latest = {}) {
  const rows = statuses.map((status, index) => ({
    id: `import_${index}`,
    dataset: { importStatus: status },
    isConnected: true,
    replaceWith(replacement) {
      this.replacement = replacement
    },
    remove() {
      this.removed = true
    },
  }))
  const requests = []
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
  install("window", {
    location: { href: "http://localhost/imports?page=2&sort=status" },
  })
  install("document", {
    importNode: (node, deep) => {
      assert.equal(deep, true)
      return { ...node }
    },
  })
  install(
    "DOMParser",
    class {
      parseFromString(html, type) {
        assert.equal(html, "latest HTML")
        assert.equal(type, "text/html")
        return { getElementById: (id) => latest[id] }
      }
    },
  )
  install("fetch", async (...args) => {
    requests.push(args)
    return { ok: true, text: async () => "latest HTML" }
  })
  t.mock.method(console, "warn", (...args) => warnings.push(args))
  const controller = new ImportsController()
  controller.element = {
    querySelectorAll: () => rows,
    contains: (row) => rows.includes(row),
  }
  return { controller, rows, requests, warnings, install }
}

test("sync recovers missed updates and deletes vanished imports on the current page", async (t) => {
  const { controller, rows, requests } = fixture(
    t,
    ["processing", "created", "deleting", "completed", "failed", "processing"],
    { import_0: { status: "completed" }, import_1: { status: "failed" } },
  )

  await controller.sync()

  assert.deepEqual(requests, [
    [
      window.location.href,
      { headers: { Accept: "text/html" }, credentials: "same-origin" },
    ],
  ])
  assert.deepEqual(rows[0].replacement, { status: "completed" })
  assert.deepEqual(rows[1].replacement, { status: "failed" })
  assert.equal(rows[2].removed, true)
  for (const row of rows.slice(3)) {
    assert.equal(row.replacement, undefined)
    assert.equal(row.removed, undefined)
  }
})

test("final statuses do not trigger a page request", async (t) => {
  const { controller, requests } = fixture(t, ["completed", "failed"])
  await controller.sync()
  assert.equal(requests.length, 0)
})

test("a late fetch cannot overwrite a newer Turbo row", async (t) => {
  const { controller, rows, install } = fixture(t, ["processing", "deleting"], {
    import_0: { status: "processing" },
  })
  let finish
  install(
    "fetch",
    () =>
      new Promise((resolve) => {
        finish = resolve
      }),
  )
  const pending = controller.sync()
  rows[0].isConnected = false
  controller.element.contains = () => false
  finish({ ok: true, text: async () => "latest HTML" })
  await pending
  assert.equal(rows[0].replacement, undefined)
  assert.equal(rows[1].removed, undefined)
})

test("simultaneous sync calls issue only one request", async (t) => {
  const { controller, requests } = fixture(t, ["processing"])
  const pending = controller.sync()
  await controller.sync()
  await pending
  assert.equal(requests.length, 1)
})

test("a failed request leaves rows intact and allows the next sync", async (t) => {
  const { controller, rows, warnings, install } = fixture(t, ["processing"], {
    import_0: { status: "completed" },
  })
  const successfulFetch = globalThis.fetch
  install("fetch", async () => ({ ok: false, status: 503 }))
  await controller.sync()
  assert.equal(rows[0].replacement, undefined)
  assert.equal(warnings.length, 1)
  install("fetch", successfulFetch)
  await controller.sync()
  assert.deepEqual(rows[0].replacement, { status: "completed" })
})
