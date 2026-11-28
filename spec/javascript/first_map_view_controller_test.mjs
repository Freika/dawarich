import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/first_map_view_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}\n//# sourceURL=first_map_view_controller.js`).toString("base64")}`
const { default: FirstMapViewController } = await import(moduleUrl)

const appended = []
globalThis.document = {
  querySelector: () => ({ content: "token" }),
  createElement: () => ({ dataset: {} }),
  body: { appendChild: (node) => appended.push(node) },
}

// fetch that answers each POST only when the test resolves it.
function deferredFetch() {
  const calls = []
  globalThis.fetch = (_url, { body }) =>
    new Promise((resolve) => {
      calls.push({
        period: JSON.parse(body),
        answer: (status) =>
          resolve({ ok: true, json: async () => ({ status }) }),
      })
    })
  return calls
}

function controller() {
  const instance = new FirstMapViewController()
  instance.urlValue = "/analytics/first_map_view"
  instance.element = {
    removed: false,
    remove() {
      this.removed = true
    },
  }
  return instance
}

const loaded = (startDate, endDate) => ({ detail: { startDate, endDate } })
const settle = () => new Promise((resolve) => setImmediate(resolve))

test("checks the same period only once", async () => {
  const calls = deferredFetch()
  const view = controller()

  const first = view.check(loaded("2026-01-01", "2026-01-31"))
  calls[0].answer("no_imported_data")
  await first
  await view.check(loaded("2026-01-01", "2026-01-31"))

  assert.equal(calls.length, 1)
})

test("checks a period that loaded while another check was in flight", async () => {
  const calls = deferredFetch()
  const view = controller()

  const first = view.check(loaded("2026-01-01", "2026-01-31"))
  view.check(loaded("2026-02-01", "2026-02-28"))
  calls[0].answer("no_imported_data")
  await settle()

  assert.equal(calls.length, 2)
  assert.equal(calls[1].period.start_at, "2026-02-01")
  calls[1].answer("recorded")
  await first

  assert.equal(view.element.removed, true)
  assert.equal(
    appended.at(-1).dataset.analyticsEventNameValue,
    "first_map_data_viewed",
  )
})
