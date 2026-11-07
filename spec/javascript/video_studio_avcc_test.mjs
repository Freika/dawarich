import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/video_studio/avcc.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { sanitizeAvcC } = await import(moduleUrl)

const fromHex = (value) =>
  Uint8Array.from(value.trim().split(/\s+/), (byte) =>
    Number.parseInt(byte, 16),
  )
const toHex = (bytes) =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(" ")

// Firefox on Windows/Linux: duplicated SPS/PPS NAL headers, lengths +1, and
// zeroed reserved bits.
const BROKEN = fromHex(`
  01 64 00 28 03 01 00 1b
  67 67 64 00 28 ac 2c ac 04 40 3c 79 78
  40 00 00 03 00 40 00 00 0f 03 68 22 11 4e
  01 00 05 68 68 ce 3c 30
`)

// What a spec-compliant encoder (Chromium, FFmpeg) produces for the same SPS
// and PPS.
const FIXED = fromHex(`
  01 64 00 28 ff e1 00 1a
  67 64 00 28 ac 2c ac 04 40 3c 79 78
  40 00 00 03 00 40 00 00 0f 03 68 22 11 4e
  01 00 04 68 ce 3c 30
`)

// Optional High-profile extension: chroma_format=1, bit depths 0/0, no SPS
// extensions. Its reserved bits are already all ones.
const HIGH_PROFILE_EXT = fromHex("fd f8 f8 00")

test("removes duplicated SPS/PPS NAL headers and fixes the lengths", () => {
  const sanitized = sanitizeAvcC(BROKEN)

  assert.ok(sanitized)
  assert.equal(toHex(sanitized), toHex(FIXED))
})

test("leaves an already canonical record untouched", () => {
  assert.equal(sanitizeAvcC(FIXED), null)
})

test("preserves the High-profile extension bytes", () => {
  const expected = new Uint8Array([...FIXED, ...HIGH_PROFILE_EXT])
  const sanitized = sanitizeAvcC(
    new Uint8Array([...BROKEN, ...HIGH_PROFILE_EXT]),
  )

  assert.ok(sanitized)
  assert.equal(toHex(sanitized), toHex(expected))
})

test("canonicalizes reserved bits even without a duplicated header", () => {
  const nonCanonical = new Uint8Array(FIXED)
  nonCanonical[4] = 0x03
  nonCanonical[5] = 0x01

  const sanitized = sanitizeAvcC(nonCanonical)

  assert.ok(sanitized)
  assert.equal(toHex(sanitized), toHex(FIXED))
})

test("accepts an ArrayBuffer and a DataView", () => {
  assert.equal(toHex(sanitizeAvcC(BROKEN.buffer)), toHex(FIXED))

  const view = new DataView(BROKEN.buffer, BROKEN.byteOffset, BROKEN.byteLength)
  assert.equal(toHex(sanitizeAvcC(view)), toHex(FIXED))
})

test("ignores a truncated record", () => {
  assert.equal(sanitizeAvcC(BROKEN.subarray(0, 12)), null)
})

test("ignores a record without parameter sets", () => {
  assert.equal(sanitizeAvcC(fromHex("01 64 00 28 ff e0 00")), null)
})

test("ignores a non-AVC description", () => {
  assert.equal(sanitizeAvcC(fromHex("00 01 02 03 04 05 06")), null)
  assert.equal(sanitizeAvcC(undefined), null)
})
