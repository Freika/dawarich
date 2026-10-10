import assert from "node:assert/strict"
import { test } from "node:test"
import { crc32, inflateSync } from "node:zlib"
import { layoutById } from "../../app-phoenix/assets/js/poster/data/layouts.js"
import { resolveTheme } from "../../app-phoenix/assets/js/poster/data/theme_loader.js"
import { exportPoster } from "../../app-phoenix/assets/js/poster/export/render.js"

const theme = resolveTheme({
  bg: "#101010",
  text: "#fafafa",
  water: "#0000ff",
  parks: "#00ff00",
  road_default: "#666666",
})
const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xdb, 7, 7, 7, 0xff, 0xd9])

function syntheticCanvas(width, height) {
  const pixels = new Uint8ClampedArray(width * height * 4)
  for (let i = 0; i < pixels.length; i++) pixels[i] = (i * 7) % 251
  const context = {
    createLinearGradient: () => ({ addColorStop() {} }),
    fillRect() {},
    fillText() {},
    beginPath() {},
    moveTo() {},
    lineTo() {},
    stroke() {},
    save() {},
    restore() {},
    getImageData: (x, y, w, h) => {
      assert.deepEqual([x, y, w, h], [0, 0, width, height])
      return { data: pixels.slice() }
    },
  }
  return {
    width,
    height,
    pixels,
    getContext: () => context,
    toBlob(callback, type, quality) {
      this.jpegRequest = [type, quality]
      callback(new Blob([jpeg], { type }))
    },
  }
}

async function render(layoutId, format, dpi, maxDimensionPx = 8192) {
  let captured
  const result = await exportPoster({
    style: { version: 8 },
    bounds: [
      [13.3, 52.4],
      [13.5, 52.6],
    ],
    layout: layoutById(layoutId),
    dpi,
    format,
    theme,
    text: { title: "Berlin", subtitle: "", coords: "" },
    font: "Poster",
    maxDimensionPx,
    capture: async ({ width, height, cssSize }) => {
      captured = syntheticCanvas(width, height)
      captured.cssSize = cssSize
      return captured
    },
    cssSize: { width: 300, height: 424 },
  })
  return {
    ...result,
    captured,
    bytes: new Uint8Array(await result.blob.arrayBuffer()),
  }
}

function pngChunks(png) {
  const view = new DataView(png.buffer, png.byteOffset, png.byteLength)
  const chunks = {}
  let offset = 8
  while (offset < png.length) {
    const length = view.getUint32(offset)
    const type = new TextDecoder().decode(png.subarray(offset + 4, offset + 8))
    const body = png.subarray(offset + 4, offset + 8 + length)
    assert.equal(
      view.getUint32(offset + 8 + length),
      crc32(body),
      `${type} CRC`,
    )
    chunks[type] = png.subarray(offset + 8, offset + 8 + length)
    offset += 12 + length
  }
  return chunks
}

const uint32 = (bytes, at) =>
  new DataView(bytes.buffer, bytes.byteOffset).getUint32(at)

test("poster PNG preserves effective DPI and decodable pixels", async () => {
  const { bytes, geometry, extension, blob, captured } = await render(
    "print-a5",
    "png",
    300,
    300,
  )
  assert.equal(extension, "png")
  assert.equal(blob.type, "image/png")
  assert.deepEqual(
    [
      geometry.effectiveDpi,
      geometry.width,
      geometry.height,
      geometry.steppedDown,
    ],
    [36, 210, 298, true],
  )
  const chunks = pngChunks(bytes)
  assert.deepEqual([uint32(chunks.IHDR, 0), uint32(chunks.IHDR, 4)], [210, 298])
  assert.deepEqual(
    [uint32(chunks.pHYs, 0), uint32(chunks.pHYs, 4), chunks.pHYs[8]],
    [1417, 1417, 1],
  )
  const raw = inflateSync(chunks.IDAT)
  const stride = 210 * 4
  assert.equal(raw.length, (stride + 1) * 298)
  for (const row of [0, 149, 297]) {
    assert.equal(raw[row * (stride + 1)], 0)
    assert.deepEqual(
      [...raw.subarray(row * (stride + 1) + 1, (row + 1) * (stride + 1))],
      [...captured.pixels.subarray(row * stride, (row + 1) * stride)],
    )
  }
  assert.deepEqual(captured.cssSize, { width: 300, height: 424 })
})

test("paper PDF preserves physical page and JPEG image", async () => {
  const { bytes, extension, blob, geometry, captured } = await render(
    "print-a4-landscape",
    "pdf",
    150,
  )
  assert.equal(extension, "pdf")
  assert.equal(blob.type, "application/pdf")
  assert.deepEqual([geometry.width, geometry.height], [1754, 1240])
  assert.deepEqual(captured.jpegRequest, ["image/jpeg", 0.92])
  const text = new TextDecoder("latin1").decode(bytes)
  assert.ok(text.startsWith("%PDF-1.4\n"))
  assert.match(text, /\/MediaBox \[0 0 841\.89 595\.28\]/)
  assert.match(
    text,
    /\/Width 1754 \/Height 1240 .*\/Filter \/DCTDecode \/Length 9/,
  )
  assert.match(text, /841\.89 0 0 595\.28 0 0 cm/)
  const image = text.indexOf("stream\n") + 7
  assert.deepEqual([...bytes.subarray(image, image + jpeg.length)], [...jpeg])
  const xref = Number(/startxref\n(\d+)\n%%EOF\n$/.exec(text)[1])
  for (const [index, match] of [
    ...text.slice(xref).matchAll(/(\d{10}) 00000 n /g),
  ].entries()) {
    assert.ok(text.slice(Number(match[1])).startsWith(`${index + 1} 0 obj`))
  }
})

test("social PDF selection preserves existing PNG fallback", async () => {
  const { bytes, extension, blob, geometry } = await render(
    "social-ig-square",
    "pdf",
    300,
  )
  assert.equal(extension, "png")
  assert.equal(blob.type, "image/png")
  assert.equal(geometry.effectiveDpi, 0)
  const chunks = pngChunks(bytes)
  assert.deepEqual(
    [uint32(chunks.IHDR, 0), uint32(chunks.IHDR, 4)],
    [1080, 1080],
  )
  assert.equal(chunks.pHYs, undefined)
})
