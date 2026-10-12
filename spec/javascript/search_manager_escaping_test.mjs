import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/search_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const stubbedSource = source
  .replace('import { translate } from "i18n"', "const translate = (key) => key")
  .replace(
    'import { LocationSearchService } from "../services/location_search_service.js"',
    "class LocationSearchService {}",
  )
const { SearchManager } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

function browserTextToHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function fakeElement() {
  let text = ""
  let html = ""
  const listenerTarget = { addEventListener: () => {} }
  return {
    set textContent(value) {
      text = String(value)
      html = browserTextToHtml(text)
    },
    get textContent() {
      return text
    },
    set innerHTML(value) {
      html = value
    },
    get innerHTML() {
      return html
    },
    querySelector: () => listenerTarget,
    remove: () => {},
  }
}

function installFakeDocument(t) {
  const appended = []
  const originalDocument = globalThis.document
  globalThis.document = {
    getElementById: () => null,
    createElement: () => fakeElement(),
    body: { appendChild: (element) => appended.push(element) },
  }
  t.after(() => {
    globalThis.document = originalDocument
  })
  return appended
}

test("create-visit modal keeps quoted place names inside the name input value", (t) => {
  const appended = installFakeDocument(t)
  const manager = new SearchManager(null, "key")

  manager.openCreateVisitModal({
    name: 'Gaststätte "Zur Linde" onmouseover="alert(1)',
    latitude: 51.34,
    longitude: 12.37,
    started_at: "2026-09-01T10:00:00Z",
    ended_at: "2026-09-01T11:00:00Z",
  })

  const html = appended[0].innerHTML
  const valueAttribute = html.match(/name="name"[^>]*value="([^"]*)"/)

  assert.ok(valueAttribute, "name input should carry a value attribute")
  assert.equal(
    valueAttribute[1],
    "Gaststätte &quot;Zur Linde&quot; onmouseover=&quot;alert(1)",
  )
  assert.doesNotMatch(html, /onmouseover="/)
})

test("escapeHtml escapes quotes and markup without a DOM", () => {
  const manager = new SearchManager(null, "key")

  assert.equal(
    manager.escapeHtml(`<b>"Tom's" & co</b>`),
    "&lt;b&gt;&quot;Tom&#39;s&quot; &amp; co&lt;/b&gt;",
  )
  assert.equal(manager.escapeHtml(null), "")
})
