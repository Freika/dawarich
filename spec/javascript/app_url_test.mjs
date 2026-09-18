import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/services/app_url.js", import.meta.url),
  "utf8",
)
const { appUrl } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function withRelativeUrlRoot(content, run) {
  globalThis.document = {
    querySelector: (selector) =>
      selector === 'meta[name="relative-url-root"]' && content !== null
        ? { content }
        : null,
  }

  try {
    run()
  } finally {
    delete globalThis.document
  }
}

test("leaves paths unchanged when the app is served at the domain root", () => {
  withRelativeUrlRoot(null, () => {
    assert.equal(appUrl("/api/v1/points?page=2"), "/api/v1/points?page=2")
    assert.equal(appUrl("/cable"), "/cable")
  })
})

test("prefixes paths with the relative URL root the layout exposes", () => {
  withRelativeUrlRoot("/dawarich", () => {
    assert.equal(
      appUrl("/api/v1/points?page=2"),
      "/dawarich/api/v1/points?page=2",
    )
    assert.equal(
      appUrl("/api/v1/tiles/points/{z}/{x}/{y}.mvt"),
      "/dawarich/api/v1/tiles/points/{z}/{x}/{y}.mvt",
    )
    assert.equal(appUrl("/cable"), "/dawarich/cable")
  })
})
