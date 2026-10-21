import assert from "node:assert/strict"
import test from "node:test"
import { createVisitResults } from "../../assets/js/map/ui/search_visits.js"
import { miniDocument } from "./support/mini_dom.mjs"

const locations = {
  total_locations: 1,
  locations: [
    {
      place_name: "Sterndamm",
      address: "Berlin",
      coordinates: [52.45, 13.5],
      total_visits: 2,
      visits: [2025, 2024].map((year) => ({
        date: `${year}-10-15T10:00:00Z`,
        coordinates: [52.45, 13.5],
        duration_estimate: "1 hour",
        visit_details: {
          start_time: `${year}-10-15T10:00:00Z`,
          end_time: `${year}-10-15T11:00:00Z`,
        },
      })),
    },
  ],
}

test("visit results render the Rails location, year and visit rows in the results box", async () => {
  const document = miniDocument()
  const container = document.createElement("div")
  container.className = "absolute hidden"
  const pushed = []
  const results = createVisitResults({
    container,
    document,
    translate: (key) => key,
    timezone: () => "Europe/Berlin",
    search: { visits: async () => locations },
    flyTo() {},
    pushEvent: (name, payload) => pushed.push([name, payload]),
  })
  await results.open({ name: "Sterndamm", lat: 52.45, lon: 13.5 })

  assert.equal(container.classList.contains("hidden"), false)
  assert.equal(container.children[0].className, "p-4 border-b bg-base-200")
  const location = container.querySelector(".location-result")
  assert.equal(location.className, "location-result border-b")
  const toggles = container.querySelectorAll(".year-toggle")
  assert.deepEqual(
    toggles.map((toggle) => toggle.getAttribute("data-year")),
    ["2024", "2025"],
  )
  const visits = container.querySelectorAll(".year-visits")
  assert.equal(visits[0].classList.contains("hidden"), true)
  toggles[0].click()
  assert.equal(visits[0].classList.contains("hidden"), false)

  const row = container.querySelector(".visit-item")
  assert.equal(
    row.className,
    "visit-item text-xs py-2 px-4 border-b hover:bg-base-300 cursor-pointer",
  )
  row.click()
  assert.equal(pushed[0][0], "visit:new")
  assert.equal(pushed[0][1].name, "Sterndamm")
  results.destroy()
})

test("no visits show the Rails empty state", async () => {
  const document = miniDocument()
  const container = document.createElement("div")
  const results = createVisitResults({
    container,
    document,
    translate: (key) => key,
    timezone: () => "UTC",
    search: { visits: async () => ({ locations: [] }) },
    flyTo() {},
    pushEvent() {},
  })
  await results.open({ name: "Nowhere", lat: 1, lon: 2 })
  assert.equal(
    container.children[0].className,
    "p-6 text-center text-base-content/60",
  )
  results.destroy()
})
