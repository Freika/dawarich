import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")
const componentPath = path.join(
  repoRoot,
  "app/javascript/maps_maplibre/components/visit_place_search.js",
)

const timers = []
const requests = []
let responses = []

const context = {
  setTimeout(fn) {
    timers.push(fn)
    return timers.length
  },
  clearTimeout(id) {
    if (id) timers[id - 1] = null
  },
  URLSearchParams,
  AbortController,
  fetch: async (url) => {
    requests.push(new URL(url, "http://localhost").searchParams.get("q"))
    const body = responses.shift()
    return { json: async () => body }
  },
  document: {
    createElement() {
      return {
        _text: "",
        set textContent(value) {
          this._text = String(value)
        },
        get innerHTML() {
          return this._text
        },
      }
    },
  },
  translate: (key) => key,
}
vm.createContext(context)
const source = (await readFile(componentPath, "utf8"))
  .replace(/^import .*\n/gm, "")
  .replace("export class VisitPlaceSearch", "class VisitPlaceSearch")
  .concat("\nglobalThis.VisitPlaceSearch = VisitPlaceSearch\n")
vm.runInContext(source, context)

const burgerKing = {
  id: null,
  name: "Burger King",
  latitude: 52.514,
  longitude: 13.3373,
}

function buildSearch(value) {
  timers.length = 0
  requests.length = 0
  const search = new context.VisitPlaceSearch(42, 52.5139, 13.337, {})
  search.input = { value }
  search.list = {
    innerHTML: "",
    querySelectorAll: () => [],
    querySelector: () => null,
  }
  return search
}

async function fireTimers() {
  const pending = timers.splice(0).filter(Boolean)
  for (const fn of pending) await fn()
}

test("a lookup the rate limiter skipped is retried and its results rendered", async () => {
  const search = buildSearch("burger king")
  responses = [
    { places: [], throttled: true },
    { places: [burgerKing], throttled: false },
  ]

  await search.fetchResults("burger king")
  assert.doesNotMatch(search.list.innerHTML, /create_here/)

  await fireTimers()

  assert.deepEqual(requests, ["burger king", "burger king"])
  assert.match(search.list.innerHTML, /Burger King/)
})

test("a skipped lookup is retried only once", async () => {
  const search = buildSearch("burger king")
  responses = [
    { places: [], throttled: true },
    { places: [], throttled: true },
  ]

  await search.fetchResults("burger king")
  await fireTimers()
  await fireTimers()

  assert.equal(requests.length, 2)
  assert.match(search.list.innerHTML, /create_here/)
})

test("typing again cancels the pending retry of the old query", async () => {
  const search = buildSearch("burger")
  responses = [{ places: [], throttled: true }]

  await search.fetchResults("burger")
  search.input.value = "burger king"
  search.onInput()
  responses = [{ places: [burgerKing], throttled: false }]
  await fireTimers()

  assert.deepEqual(requests, ["burger", "burger king"])
})

test("a skipped lookup answered after the next keystroke is not retried", async () => {
  const search = buildSearch("burger")
  responses = [
    { places: [], throttled: true },
    { places: [burgerKing], throttled: false },
  ]

  const pending = search.fetchResults("burger")
  search.input.value = "burger king"
  search.onInput()
  await pending
  await fireTimers()
  await fireTimers()

  assert.deepEqual(requests, ["burger", "burger king"])
  assert.match(search.list.innerHTML, /Burger King/)
})

test("closing the panel cancels a pending retry", async () => {
  const search = buildSearch("burger king")
  search.mount = { innerHTML: "" }
  responses = [{ places: [], throttled: true }]

  await search.fetchResults("burger king")
  search.close()
  await fireTimers()

  assert.deepEqual(requests, ["burger king"])
})
