import assert from "node:assert/strict"
import test from "node:test"

const { encodePdf } = await import(
  new URL(
    "../../app/javascript/poster_studio/export/pdf_encoder.js",
    import.meta.url,
  )
)

const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xd9])
const fakeCanvas = {
  width: 3543,
  height: 4724,
  toBlob: (callback) => callback(new Blob([JPEG])),
}

async function pdfText(options) {
  return new TextDecoder("latin1").decode(await encodePdf(fakeCanvas, options))
}

const box = (text, name) =>
  text
    .match(new RegExp(`/${name} \\[([^\\]]+)\\]`))?.[1]
    .split(" ")
    .map(Number)

test("bleed grows the page by bleed on every side and marks the trim", async () => {
  const text = await pdfText({ widthMm: 300, heightMm: 400, bleedMm: 4 })

  // Gelato's 30x40 poster requires exactly 308 x 408 mm.
  assert.deepEqual(box(text, "MediaBox"), [0, 0, 873.07, 1156.54])
  assert.deepEqual(box(text, "BleedBox"), [0, 0, 873.07, 1156.54])
  assert.deepEqual(box(text, "TrimBox"), [11.34, 11.34, 861.73, 1145.2])
})

test("bleed fills the margin with mirrored copies around the centred image", async () => {
  const text = await pdfText({ widthMm: 300, heightMm: 400, bleedMm: 4 })
  const draws = [...text.matchAll(/([-\d. ]+) cm\n\/Im0 Do/g)].map((m) =>
    m[1].trim().split(" ").map(Number),
  )

  assert.equal(draws.length, 9)
  // Centre copy last, so it paints over any seam the mirrored copies leave.
  assert.deepEqual(draws.at(-1), [850.39, 0, 0, 1133.86, 11.34, 11.34])
  // Left neighbour mirrors across the trim's left edge.
  assert.ok(
    draws.some(
      (d) => d.join() === [-850.39, 0, 0, 1133.86, 11.34, 11.34].join(),
    ),
  )
  // Top-right corner mirrors on both axes across the far trim edges.
  assert.ok(
    draws.some(
      (d) => d.join() === [-850.39, 0, 0, -1133.86, 1712.12, 2279.06].join(),
    ),
  )
})

test("no bleed keeps the plain single-draw page used for downloads", async () => {
  const text = await pdfText({ widthMm: 300, heightMm: 400 })

  assert.deepEqual(box(text, "MediaBox"), [0, 0, 850.39, 1133.86])
  assert.equal(box(text, "TrimBox"), undefined)
  assert.equal(text.match(/\/Im0 Do/g).length, 1)
})
