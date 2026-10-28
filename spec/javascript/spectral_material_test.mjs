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

test("keeps unvisited members outlined in the same frame as the complete collection", () => {
  const html = spectralMarkup({
    ...options,
    silhouette: {
      path: "M0 0L0 -1L2 -1L2 0Z",
      unvisited_path: "M1 0L1 -1L2 -1L2 0Z",
      viewbox: "0 -1 2 1",
    },
  }).html
  assert.match(html, /class="geo-unvisited" d="M 150\.0000 /)
  assert.ok(
    html.indexOf('class="geo-unvisited"') >
      html.indexOf('class="geo-foil-composite"'),
  )
  assert.ok(!spectralMarkup(options).html.includes('class="geo-unvisited"'))
})

test("rejects unsupported markup in an unvisited member path", () => {
  assert.equal(
    spectralMarkup({
      ...options,
      silhouette: {
        ...options.silhouette,
        unvisited_path: '\"><script>alert(1)</script>',
      },
    }),
    "",
  )
})

test("preserves globe coastlines and graticules above unvisited areas and scales their strokes", () => {
  const html = spectralMarkup({
    ...options,
    silhouette: {
      path: "M0 0L10 0L10 10L0 10Z",
      viewbox: "0 0 10 10",
      unvisited_path: "M0 5L10 5L10 10L0 10Z",
      details: [
        {
          path: "M0 5L10 5",
          fill: "none",
          stroke: "#abc123",
          stroke_width: 0.5,
          opacity: 0.8,
        },
      ],
    },
  }).html
  assert.match(
    html,
    /class="geo-detail" d="M [\d.]+ [\d.]+ L [\d.]+ [\d.]+" fill="none" stroke="#abc123" stroke-width="11.8" opacity="0.8"/,
  )
  assert.ok(
    html.indexOf('class="geo-detail"') > html.indexOf('class="geo-unvisited"'),
  )
})

test("rejects markup, external paint servers and non-finite globe detail attributes", () => {
  const base = {
    path: "M0 0L1 1",
    fill: "none",
    stroke: "#abc123",
    stroke_width: 0.2,
    opacity: 0.8,
  }
  for (const invalid of [
    { path: "<script/>" },
    { fill: "url(https://example.test/a)" },
    { stroke: '" onload="alert(1)' },
    { stroke_width: Infinity },
    { opacity: 2 },
  ]) {
    const html = spectralMarkup({
      ...options,
      silhouette: { ...options.silhouette, details: [{ ...base, ...invalid }] },
    }).html
    assert.ok(!html.includes('class="geo-detail"'))
    assert.ok(!html.includes("onload="))
  }
})
