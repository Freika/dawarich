import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const source = readFileSync(
  new URL(
    "../../app/javascript/achievements/spectral_material.js",
    import.meta.url,
  ),
  "utf8",
)
const { spectralMarkup } = await import(
  "data:text/javascript;base64," + Buffer.from(source).toString("base64")
)
const options = {
  silhouette: {
    path: "M 11 -48 L 11 -49 12 -49 12 -48 Z",
    viewbox: "11 -49 1 1",
  },
  key: "DE-BY",
  rarity: "Legendary",
  uid: "test-card",
  paperAsset: "/assets/paper.webp",
  foilAsset: "/assets/foil.webp",
}

test("uses two shared assets and deterministic geography-specific material crops", () => {
  const first = spectralMarkup(options)
  assert.deepEqual(first, spectralMarkup(options))
  assert.notEqual(first.html, spectralMarkup({ ...options, key: "BR-SP" }).html)
  assert.deepEqual(
    [
      ...new Set(
        [...first.html.matchAll(/<image[^>]+href="([^"]+)"/g)].map((m) => m[1]),
      ),
    ].sort(),
    ["/assets/foil.webp", "/assets/paper.webp"],
  )
  assert.equal(first.accent, "#efb348")
  assert.ok(first.html.includes("data-spectrum"))
  assert.ok(!first.html.includes("journey-route"))
  assert.ok(!first.html.includes("geo-relit"))
})

test("normalizes polygon coordinates without transforming the foil gradients", () => {
  const html = spectralMarkup(options).html
  assert.match(
    html,
    /id="geography-test-card" d="M [\d.]+ 248.0000 L [\d.]+ 12.0000/,
  )
  assert.ok(!html.includes('transform="matrix('))
  assert.ok(!html.includes("NaN"))
})

test("supports all rarities with a safe fallback", () => {
  for (const rarity of ["Common", "Rare", "Epic", "Legendary", "Unknown"]) {
    assert.ok(
      spectralMarkup({ ...options, rarity }).html.includes(
        "geo-foil-composite",
      ),
    )
  }
})

test("rejects degenerate geometry and escapes labels and asset attributes", () => {
  assert.equal(
    spectralMarkup({
      ...options,
      silhouette: { ...options.silhouette, viewbox: "0 0 0 1" },
    }),
    "",
  )
  assert.equal(
    spectralMarkup({
      ...options,
      silhouette: { ...options.silhouette, path: "<script>alert(1)</script>" },
    }),
    "",
  )
  const html = spectralMarkup({
    ...options,
    key: '"><script>alert(1)</script>',
    paperAsset: '/a" onload="alert(1)',
  }).html
  assert.ok(!html.includes("<script>"))
  assert.ok(!html.includes(' onload="'))
})
