import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadModule(relativePath, dependencies = "") {
  const source = await readFile(new URL(relativePath, import.meta.url), "utf8")
  const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const url = `data:text/javascript;base64,${Buffer.from(
    `${dependencies}\n${withoutImports}`,
  ).toString("base64")}`

  return import(url)
}

let capturedHTML = ""

const { PhotosLayer } = await loadModule(
  "../../app/javascript/maps_maplibre/layers/photos_layer.js",
  `
    const translate = (key) => key
    const formatTimestamp = (value) => String(value)
    const getCurrentTheme = () => "light"
    const getThemeColors = () => ({
      backgroundAlt: "#fff",
      textPrimary: "#000",
      textSecondary: "#333",
      textMuted: "#666",
    })
    class BaseLayer {}
    const escapeHtml = (value) =>
      value == null
        ? ""
        : String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    const escapeAttribute = (value) =>
      escapeHtml(value).replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    const maplibregl = {
      Popup: class {
        setLngLat() { return this }
        setHTML(html) { globalThis.__capture(html); return this }
        addTo() { return this }
      },
    }
  `,
)

globalThis.__capture = (html) => {
  capturedHTML = html
}

function showHostilePopup() {
  const layer = Object.create(PhotosLayer.prototype)
  layer.timezone = "UTC"
  layer.map = {}
  capturedHTML = ""

  layer.showPhotoPopup({
    geometry: { coordinates: [13.4, 52.5] },
    properties: {
      thumbnail_url: 'x" onerror="alert(4)',
      taken_at: 1_700_000_000,
      filename: '"><script>alert(1)</script>',
      city: "<img src=x onerror=alert(2)>",
      state: null,
      country: null,
      type: "IMAGE",
      source: "<svg onload=alert(3)>",
    },
  })

  return capturedHTML
}

test("the photo popup escapes hostile metadata instead of emitting markup", () => {
  const html = showHostilePopup()

  assert.ok(html.length > 0, "expected the popup to be rendered")
  assert.ok(!html.includes("<script>"), "filename injected a script tag")
  assert.ok(!html.includes("<img src=x"), "city injected an img tag")
  assert.ok(!html.includes("<svg onload"), "source injected an svg tag")
  // The hostile thumbnail_url is `x" onerror="alert(4)`: unescaped it closes
  // src and opens a live onerror handler. Escaped, the quote becomes &quot;.
  assert.ok(
    !html.includes('src="x"'),
    "thumbnail_url broke out of the src attribute",
  )
  assert.ok(
    html.includes("&quot;"),
    "quotes in attribute values were not escaped",
  )
})

test("the photo popup still shows the escaped metadata", () => {
  const html = showHostilePopup()

  assert.ok(
    html.includes("&lt;script&gt;"),
    "filename was dropped instead of escaped",
  )
  assert.ok(
    html.includes("&lt;img src=x"),
    "city was dropped instead of escaped",
  )
})
