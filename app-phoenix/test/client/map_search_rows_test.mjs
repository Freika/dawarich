import assert from "node:assert/strict"
import test from "node:test"
import { createSearchUi } from "../../assets/js/map/ui/search.js"
import { miniDocument } from "./support/mini_dom.mjs"

function setup(suggest) {
  const document = miniDocument()
  const input = document.createElement("input")
  input.value = ""
  const results = document.createElement("div")
  results.className = "absolute hidden"
  const picked = []
  let pending = null
  const ui = createSearchUi({
    input,
    results,
    document,
    translate: (key) => key,
    search: { suggest, cancel() {} },
    onSelect: (item) => picked.push(item),
    timers: {
      setTimeout: (fn) => {
        pending = fn
        return 1
      },
      clearTimeout() {},
    },
  })
  const type = async (value) => {
    input.value = value
    input.dispatch("input")
    const run = pending
    pending = null
    const done = run?.()
    return done
  }
  return { ui, input, results, picked, type }
}

test("suggestions render as Rails search result rows and Enter picks the first", async () => {
  const { input, results, picked, type } = setup(async () => ({
    status: "ok",
    suggestions: [
      { name: "Sterndamm", address: "Berlin", lat: 52.45, lon: 13.5 },
      { name: "Sternstraße", lat: 52.5, lon: 13.4 },
    ],
  }))
  await type("Stern")
  const rows = results.querySelectorAll(".search-result-item")
  assert.equal(rows.length, 2)
  assert.equal(
    rows[0].className,
    "search-result-item p-3 hover:bg-base-200 cursor-pointer rounded-lg transition-colors",
  )
  assert.equal(rows[0].children[0].className, "font-medium text-sm")
  assert.equal(
    rows[0].children[1].className,
    "text-xs text-base-content/60 mt-1",
  )
  assert.equal(rows[0].children[1].textContent, "Berlin")
  assert.equal(rows[1].children.length, 1)
  assert.equal(results.classList.contains("hidden"), false)

  input.dispatch("keydown", { key: "Enter" })
  assert.equal(picked[0].name, "Sterndamm")
  assert.equal(input.value, "Sterndamm")
})

test("an empty answer shows the Rails no-locations line, a short query clears", async () => {
  const { results, type } = setup(async () => ({
    status: "ok",
    suggestions: [],
  }))
  await type("Zzz")
  assert.equal(
    results.children[0].className,
    "p-3 text-sm text-base-content/60",
  )
  assert.equal(results.children[0].textContent.trim(), "search.no_locations")
  await type("Z")
  assert.equal(results.children.length, 0)
  assert.equal(results.classList.contains("hidden"), true)
})

test("a failed lookup shows the Rails error line", async () => {
  const { results, type } = setup(async () => ({ status: "error" }))
  await type("Stern")
  assert.equal(results.children[0].className, "p-3 text-sm text-error")
  assert.equal(
    results.children[0].textContent.trim(),
    "search.suggestions_failed",
  )
})
