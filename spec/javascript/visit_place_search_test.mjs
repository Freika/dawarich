import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/components/visit_place_search.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = "const translate = (key) => key\n"
const moduleUrl = `data:text/javascript;base64,${Buffer.from(
  `${dependencies}\n${withoutImports}`,
).toString("base64")}`
const { VisitPlaceSearch } = await import(moduleUrl)

globalThis.document = {
  querySelector: () => null,
  createElement: () => {
    const element = { innerHTML: "" }
    Object.defineProperty(element, "textContent", {
      set(value) {
        element.innerHTML = String(value)
          .replaceAll("&", "&amp;")
          .replaceAll("<", "&lt;")
          .replaceAll(">", "&gt;")
      },
    })
    return element
  },
}

test("a duplicate place and start time shows the translated duplicate message", async () => {
  const search = new VisitPlaceSearch(1, 0, 0, {})
  search.list = { innerHTML: "" }
  search.patchVisit = async () => {
    throw Object.assign(new Error("A visit already exists"), {
      code: "duplicate_place_start",
    })
  }

  await search.selectArea({ id: 1 })

  assert.match(search.list.innerHTML, /search\.duplicate_visit/)
})

test("other failures keep the translated generic message instead of raw error text", async () => {
  const search = new VisitPlaceSearch(1, 0, 0, {})
  search.list = { innerHTML: "" }
  search.patchVisit = async () => {
    throw new Error("PATCH /api/v1/visits/1 failed with 500")
  }

  await search.selectArea({ id: 1 })

  assert.match(search.list.innerHTML, /search\.unavailable/)
  assert.doesNotMatch(search.list.innerHTML, /failed with/)
})

test("API error payloads keep their error code", async () => {
  globalThis.fetch = async () => ({
    ok: false,
    status: 422,
    json: async () => ({
      error: "Duplicate visit",
      code: "duplicate_place_start",
    }),
  })
  const search = new VisitPlaceSearch(1, 0, 0, {})

  await assert.rejects(search.patchVisit({ place_id: 2 }), {
    code: "duplicate_place_start",
  })
})
