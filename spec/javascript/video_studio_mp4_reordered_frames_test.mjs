import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// Firefox's H.264 encoder emits B-frames: chunks arrive in decode order but
// carry presentation timestamps. Run the real vendored muxer against an
// encoder that reorders the same way and check that every frame lands in the
// file.
const muxerSource = await readFile(
  new URL("../../vendor/javascript/mp4-muxer.js", import.meta.url),
  "utf8",
)
const { ArrayBufferTarget, Muxer } = await import(
  `data:text/javascript;base64,${Buffer.from(muxerSource).toString("base64")}`
)

globalThis.EncodedVideoChunk = class {
  constructor({ type, timestamp, duration }) {
    this.type = type
    this.timestamp = timestamp
    this.duration = duration
    this.byteLength = 4
  }

  copyTo(target) {
    target.set([0, 0, 0, 1])
  }
}

// I P B P B …: each P frame is encoded before the B frame shown ahead of it.
function decodeOrder(frames) {
  const order = []
  for (let i = 0; i < frames.length; i += 2) {
    if (frames[i + 2]) order.push(frames[i + 2], frames[i + 1])
    else order.push(...frames.slice(i + 1))
  }
  return [frames[0], ...order.filter(Boolean)]
}

function fakeVideoEncoder(order) {
  function FakeVideoEncoder({ output, error }) {
    const frames = []
    return {
      state: "configured",
      encodeQueueSize: 0,
      configure() {},
      encode(frame) {
        frames.push(frame)
      },
      async flush() {
        try {
          for (const frame of order(frames)) {
            const chunk = new EncodedVideoChunk({
              type: frame.timestamp === 0 ? "key" : "delta",
              timestamp: frame.timestamp,
              duration: frame.duration,
            })
            output(
              chunk,
              frame.timestamp === 0
                ? {
                    decoderConfig: {
                      codec: "avc1.42001f",
                      description: new Uint8Array([
                        1, 66, 0, 31, 255, 225, 0, 0, 1, 0, 0,
                      ]),
                    },
                  }
                : undefined,
            )
          }
        } catch (e) {
          error(e)
        }
      },
      close() {
        this.state = "closed"
      },
      addEventListener() {},
      removeEventListener() {},
    }
  }
  FakeVideoEncoder.isConfigSupported = async () => ({ supported: true })
  globalThis.VideoEncoder = FakeVideoEncoder
  globalThis.VideoFrame = class {
    constructor(_canvas, { timestamp, duration }) {
      this.timestamp = timestamp
      this.duration = duration
    }

    close() {}
  }
}

async function loadEncoder() {
  const source = await readFile(
    new URL(
      "../../app/javascript/video_studio/mp4_encoder.js",
      import.meta.url,
    ),
    "utf8",
  )
  globalThis.testMuxer = { ArrayBufferTarget, Muxer }
  const prelude = `
const { ArrayBufferTarget, Muxer } = globalThis.testMuxer
async function pickSupportedCodec() {
  return { config: { codec: "avc1.42001f" }, muxerCodec: "avc" }
}
`
  const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const url = `data:text/javascript;base64,${Buffer.from(prelude + withoutImports).toString("base64")}`
  return import(url)
}

function boxOffset(bytes, name) {
  for (let i = 4; i + 4 <= bytes.length; i += 1) {
    if (String.fromCharCode(...bytes.subarray(i, i + 4)) === name) return i
  }
  return -1
}

function sampleCount(bytes) {
  const at = boxOffset(bytes, "stsz")
  if (at === -1) return null
  return new DataView(bytes.buffer, bytes.byteOffset).getUint32(at + 12)
}

// Run-length entries of a stts/ctts box, expanded to one value per sample.
function expandedEntries(bytes, name) {
  const view = new DataView(bytes.buffer, bytes.byteOffset)
  const at = boxOffset(bytes, name)
  const values = []
  for (let entry = 0; entry < view.getUint32(at + 8); entry += 1) {
    const offset = at + 12 + entry * 8
    for (let n = 0; n < view.getUint32(offset); n += 1) {
      values.push(view.getUint32(offset + 4))
    }
  }
  return values
}

// Presentation time of each sample, read back from the file in decode order.
function presentationTimes(bytes) {
  const deltas = expandedEntries(bytes, "stts")
  const offsets = expandedEntries(bytes, "ctts")
  let decodeTime = 0
  return offsets.map((offset, i) => {
    const time = decodeTime + offset
    decodeTime += deltas[i]
    return time
  })
}

function assertShownInOrder(bytes, frameOfSample) {
  const times = []
  presentationTimes(bytes).forEach((time, sample) => {
    times[frameOfSample[sample]] = time
  })
  const gaps = times.slice(1).map((time, i) => time - times[i])
  for (const gap of gaps) assert.ok(Math.abs(gap - gaps[0]) <= 1, `${gaps}`)
  assert.ok(gaps[0] > 0, `${gaps}`)
}

async function encodeNineFrames(order) {
  fakeVideoEncoder(order)
  const { createMp4Encoder } = await loadEncoder()
  const encoder = await createMp4Encoder({ width: 64, height: 64, fps: 30 })
  for (let i = 0; i < 9; i += 1) await encoder.addFrame({}, i)
  const blob = await encoder.finalize()
  return new Uint8Array(await blob.arrayBuffer())
}

test("muxes every frame when the encoder emits B-frames out of presentation order", async () => {
  const bytes = await encodeNineFrames(decodeOrder)

  assert.equal(sampleCount(bytes), 9)
  assert.notEqual(boxOffset(bytes, "ctts"), -1)
  assertShownInOrder(bytes, [0, 2, 1, 4, 3, 6, 5, 8, 7])
})

test("shows frames in order when the encoder reorders them more than one deep", async () => {
  const pyramid = [0, 4, 2, 1, 3, 8, 6, 5, 7]
  const bytes = await encodeNineFrames((frames) =>
    pyramid.map((frame) => frames[frame]),
  )

  assert.equal(sampleCount(bytes), 9)
  assertShownInOrder(bytes, pyramid)
})

test("writes no composition offsets when frames arrive in presentation order", async () => {
  const bytes = await encodeNineFrames((frames) => frames)

  assert.equal(sampleCount(bytes), 9)
  assert.equal(boxOffset(bytes, "ctts"), -1)
})
