import { zlibSync } from "fflate"

const SIGNATURE = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10])
const PX_PER_METER_PER_INCH = 39.37007874 // 1 / 0.0254

const CRC_TABLE = (() => {
  const table = new Uint32Array(256)
  for (let n = 0; n < 256; n += 1) {
    let c = n
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    }
    table[n] = c >>> 0
  }
  return table
})()

function crc32(bytes) {
  let crc = 0xffffffff
  for (let i = 0; i < bytes.length; i += 1) {
    crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const typeBytes = new TextEncoder().encode(type)
  const body = new Uint8Array(typeBytes.length + data.length)
  body.set(typeBytes, 0)
  body.set(data, typeBytes.length)
  const out = new Uint8Array(4 + body.length + 4)
  const view = new DataView(out.buffer)
  view.setUint32(0, data.length)
  out.set(body, 4)
  view.setUint32(4 + body.length, crc32(body))
  return out
}

function ihdr(width, height) {
  const data = new Uint8Array(13)
  const view = new DataView(data.buffer)
  view.setUint32(0, width)
  view.setUint32(4, height)
  data[8] = 8 // bit depth
  data[9] = 6 // color type RGBA
  return data
}

function phys(dpi) {
  const ppm = Math.max(1, Math.round(dpi * PX_PER_METER_PER_INCH))
  const data = new Uint8Array(9)
  const view = new DataView(data.buffer)
  view.setUint32(0, ppm)
  view.setUint32(4, ppm)
  data[8] = 1 // unit: meters
  return data
}

function filterRows(rgba, width, height) {
  const stride = width * 4
  const out = new Uint8Array((stride + 1) * height)
  for (let y = 0; y < height; y += 1) {
    const dst = y * (stride + 1)
    out[dst] = 0 // filter type: none
    out.set(rgba.subarray(y * stride, (y + 1) * stride), dst + 1)
  }
  return out
}

export function encodePng(rgba, width, height, dpi = 0) {
  if (rgba.length !== width * height * 4) {
    throw new Error(
      `RGBA length ${rgba.length} does not match ${width}x${height}x4`,
    )
  }
  const idat = zlibSync(filterRows(rgba, width, height), { level: 6 })
  const chunks = [chunk("IHDR", ihdr(width, height))]
  if (dpi > 0) chunks.push(chunk("pHYs", phys(dpi)))
  chunks.push(chunk("IDAT", idat), chunk("IEND", new Uint8Array(0)))

  const total = SIGNATURE.length + chunks.reduce((n, c) => n + c.length, 0)
  const png = new Uint8Array(total)
  png.set(SIGNATURE, 0)
  let offset = SIGNATURE.length
  for (const c of chunks) {
    png.set(c, offset)
    offset += c.length
  }
  return png
}
