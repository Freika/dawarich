import assert from "node:assert/strict"
import { test } from "node:test"
import { crc32, inflateSync } from "node:zlib"
import {
  downloadBlob,
  pdfBlob,
  pngBlob,
  posterFilename,
} from "../../app-phoenix/assets/js/poster/export/download.js"
import { encodePdf } from "../../app-phoenix/assets/js/poster/export/pdf_encoder.js"
import { encodePng } from "../../app-phoenix/assets/js/poster/export/png_encoder.js"

function chunks(png) {
  const view = new DataView(png.buffer, png.byteOffset, png.byteLength)
  const found = []
  let offset = 8
  while (offset < png.length) {
    const length = view.getUint32(offset)
    const type = new TextDecoder().decode(png.subarray(offset + 4, offset + 8))
    const body = png.subarray(offset + 4, offset + 8 + length)
    found.push({
      type,
      data: png.subarray(offset + 8, offset + 8 + length),
      crcOk: view.getUint32(offset + 8 + length) === crc32(body),
    })
    offset += 12 + length
  }
  return found
}

test("PNG carries signature, IHDR, pHYs at the effective DPI and valid CRCs", () => {
  const rgba = Uint8Array.from([255, 0, 0, 255, 0, 255, 0, 128])
  const png = encodePng(rgba, 2, 1, 300)
  assert.deepEqual([...png.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10])
  const parts = chunks(png)
  assert.deepEqual(
    parts.map((part) => part.type),
    ["IHDR", "pHYs", "IDAT", "IEND"],
  )
  assert.ok(parts.every((part) => part.crcOk))
  const ihdr = new DataView(parts[0].data.buffer, parts[0].data.byteOffset)
  assert.deepEqual(
    [ihdr.getUint32(0), ihdr.getUint32(4), parts[0].data[8], parts[0].data[9]],
    [2, 1, 8, 6],
  )
  const phys = new DataView(parts[1].data.buffer, parts[1].data.byteOffset)
  assert.deepEqual(
    [phys.getUint32(0), phys.getUint32(4), parts[1].data[8]],
    [11811, 11811, 1],
  )
  assert.deepEqual(
    [...inflateSync(parts[2].data)],
    [0, 255, 0, 0, 255, 0, 255, 0, 128],
  )
})

test("PNG omits pHYs for pixel layouts and rejects mismatched buffers", () => {
  const png = encodePng(new Uint8Array(4), 1, 1)
  assert.deepEqual(
    chunks(png).map((part) => part.type),
    ["IHDR", "IDAT", "IEND"],
  )
  assert.throws(() => encodePng(new Uint8Array(3), 1, 1), /does not match/)
})

const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 0xff, 0xd9])

function jpegCanvas(width, height) {
  return {
    width,
    height,
    toBlob(callback, type, quality) {
      this.requested = [type, quality]
      callback(new Blob([jpeg], { type }))
    },
  }
}

test("PDF page keeps the physical paper size in points and embeds the JPEG", async () => {
  const canvas = jpegCanvas(2480, 3508)
  const pdf = await encodePdf(canvas, { widthMm: 210, heightMm: 297 })
  const text = new TextDecoder("latin1").decode(pdf)
  assert.ok(text.startsWith("%PDF-1.4\n"))
  assert.deepEqual(canvas.requested, ["image/jpeg", 0.92])
  assert.match(text, /\/MediaBox \[0 0 595\.28 841\.89\]/)
  assert.match(
    text,
    /\/Width 2480 \/Height 3508 \/ColorSpace \/DeviceRGB \/BitsPerComponent 8 \/Filter \/DCTDecode \/Length 9/,
  )
  const start = text.indexOf("stream\n") + 7
  assert.deepEqual([...pdf.subarray(start, start + jpeg.length)], [...jpeg])
  const startxref = Number(/startxref\n(\d+)\n%%EOF\n$/.exec(text)[1])
  assert.ok(text.slice(startxref).startsWith("xref\n0 6\n"))
  const offsets = [...text.slice(startxref).matchAll(/(\d{10}) 00000 n /g)].map(
    (match) => Number(match[1]),
  )
  assert.equal(offsets.length, 5)
  offsets.forEach((offset, index) => {
    assert.ok(text.slice(offset).startsWith(`${index + 1} 0 obj\n`))
  })
})

test("PDF encoding rejects when the canvas cannot produce a JPEG", async () => {
  const canvas = { width: 1, height: 1, toBlob: (callback) => callback(null) }
  await assert.rejects(
    encodePdf(canvas, { widthMm: 1, heightMm: 1 }),
    /toBlob failed/,
  )
})

test("poster filenames slug theme names and keep the paper extension", () => {
  assert.equal(
    posterFilename({ name: "Midnight Blue!" }, "A3", "png"),
    "dawarich-poster-midnight-blue-A3.png",
  )
  assert.equal(
    posterFilename(null, "A4", "pdf"),
    "dawarich-poster-poster-A4.pdf",
  )
  assert.equal(pngBlob(new Uint8Array(1)).type, "image/png")
  assert.equal(pdfBlob(new Uint8Array(1)).type, "application/pdf")
})

test("downloads click a detached link and revoke their object URL afterwards", () => {
  const events = []
  const link = {
    click: () => events.push(["click", link.href, link.download]),
    remove: () => events.push(["remove"]),
  }
  const environment = {
    document: {
      createElement: () => link,
      body: { appendChild: () => events.push(["append"]) },
    },
    URL: {
      createObjectURL: () => "blob:synthetic",
      revokeObjectURL: (url) => events.push(["revoke", url]),
    },
    setTimeout: (callback, delay) => events.push(["timer", delay, callback]),
  }
  downloadBlob(new Blob(["x"]), "poster.png", environment)
  const timer = events.find((event) => event[0] === "timer")
  assert.equal(timer[1], 2000)
  timer[2]()
  assert.deepEqual(
    events.filter((event) => event[0] !== "timer"),
    [
      ["append"],
      ["click", "blob:synthetic", "poster.png"],
      ["remove"],
      ["revoke", "blob:synthetic"],
    ],
  )
})
