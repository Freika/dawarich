import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

import { escapeHtml } from "../../app/javascript/maps_maplibre/utils/escape_html.js"

const root = new URL("../../", import.meta.url).pathname
// The controller and the mixins it is split into, read as one source.
const controllerFiles = [
  "app/javascript/controllers/maps/immich_enrich_controller.js",
  "app/javascript/controllers/maps/immich_enrich/match_list.js",
  "app/javascript/controllers/maps/immich_enrich/match_markers.js",
]
const readController = async () =>
  (
    await Promise.all(
      controllerFiles.map((file) => readFile(`${root}${file}`, "utf8")),
    )
  ).join("\n")

// Regression for the Immich enrich-panel DOM XSS: an Immich filename reached a
// quoted HTML attribute and an innerHTML tooltip without quote-safe escaping.

test("escapeHtml escapes the characters that break out of an HTML attribute", () => {
  assert.equal(escapeHtml('a" onmouseover="x'), "a&quot; onmouseover=&quot;x")
  assert.equal(
    escapeHtml("<img src=x onerror=y>"),
    "&lt;img src=x onerror=y&gt;",
  )
  assert.equal(escapeHtml("a'b&c"), "a&#39;b&amp;c")
  assert.equal(escapeHtml(null), "")
})

test("the enrich controller never feeds the filename into a tooltip innerHTML", async () => {
  const src = await readController()
  assert.ok(
    !/tooltip\.innerHTML\s*=/.test(src),
    "showThumbTooltip must build the tooltip with DOM APIs, not innerHTML",
  )
  assert.match(
    src,
    /\.alt\s*=\s*name/,
    "the image alt must be assigned as a property",
  )
  assert.match(
    src,
    /\.textContent\s*=\s*name/,
    "the caption must be set via textContent",
  )
})

test("the enrich controller escapes the filename attribute with escapeHtml", async () => {
  const src = await readController()
  assert.match(
    src,
    /data-filename="\$\{escapeHtml\(match\.filename\)\}"/,
    "data-filename must be escaped with the quote-safe escapeHtml helper",
  )
})
