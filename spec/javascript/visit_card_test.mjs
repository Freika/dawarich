import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

globalThis.document = { documentElement: { lang: "en" } }

const source = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/components/visit_card.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { VisitCard } = await import(
  `data:text/javascript;base64,${Buffer.from(
    `const translate = (key) => key\nconst escapeHtml = (value) => String(value ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")\n${source}`,
  ).toString("base64")}`
)

const visit = {
  id: 1,
  name: "Lunch with Anna",
  status: "confirmed",
  started_at: "2026-10-15T12:00:00Z",
  ended_at: "2026-10-15T13:00:00Z",
  duration: 60,
  place: { id: 5, latitude: 51.3, longitude: 12.3 },
}

test("shows the place address under the visit name", () => {
  const html = VisitCard.create({
    ...visit,
    place: {
      ...visit.place,
      address: "Karl-Liebknecht-Straße 34, 04275 Leipzig",
    },
  })

  assert.match(html, /Lunch with Anna/)
  assert.match(
    html,
    /data-visit-address[^>]*>[^<]*Karl-Liebknecht-Straße 34, 04275 Leipzig/,
  )
})

test("escapes the address", () => {
  const html = VisitCard.create({
    ...visit,
    place: { ...visit.place, address: "<b>Street</b>" },
  })

  assert.match(html, /&lt;b&gt;Street&lt;\/b&gt;/)
})

test("omits the address line when the place has none", () => {
  assert.doesNotMatch(VisitCard.create(visit), /data-visit-address/)
})
