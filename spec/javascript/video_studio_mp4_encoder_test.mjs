import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// mp4_encoder reaches for the muxer and the codec negotiator, neither of which
// these cases exercise — stub both and drive the WebCodecs surface with fakes,
// the same source-rewriting approach the other video studio specs use.
const source = await readFile(
  new URL("../../app/javascript/video_studio/mp4_encoder.js", import.meta.url),
  "utf8",
)
const prelude = `
class ArrayBufferTarget { constructor() { this.buffer = new ArrayBuffer(8) } }
class Muxer { addVideoChunk() {} finalize() {} }
async function pickSupportedCodec() {
  return { config: { codec: "avc1.42001f" }, muxerCodec: "avc" }
}
`
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(prelude + withoutImports).toString("base64")}`
const { createMp4Encoder } = await import(moduleUrl)

// A VideoEncoder that never drains on its own, so any frame past the
// backpressure threshold parks until the test drains, errors, or aborts it.
function fakeVideoEncoder() {
  const listeners = []
  let raiseError = null

  const codec = {
    state: "configured",
    encodeQueueSize: 0,
    configure() {},
    encode() {
      codec.encodeQueueSize += 1
    },
    close() {
      codec.state = "closed"
    },
    async flush() {},
    addEventListener(name, fn) {
      if (name === "dequeue") listeners.push(fn)
    },
    removeEventListener(name, fn) {
      const at = listeners.indexOf(fn)
      if (name === "dequeue" && at !== -1) listeners.splice(at, 1)
    },
  }

  // A plain factory rather than a class: `new` on a function that returns an
  // object hands back that object, and a constructor may not return one.
  function FakeVideoEncoder({ error }) {
    raiseError = error
    return codec
  }
  FakeVideoEncoder.isConfigSupported = async () => ({ supported: true })
  globalThis.VideoEncoder = FakeVideoEncoder
  globalThis.VideoFrame = class {
    close() {}
  }

  return {
    codec,
    fail: (error) => raiseError(error),
    drain: () => {
      codec.encodeQueueSize = 0
      for (const fn of listeners.splice(0)) fn()
    },
  }
}

// Parks the queue above the backpressure threshold so the next addFrame waits.
async function backpressuredEncoder() {
  const fake = fakeVideoEncoder()
  const encoder = await createMp4Encoder({ width: 8, height: 8, fps: 30 })
  fake.codec.encodeQueueSize = 100
  return { fake, encoder }
}

test(
  "a hard encoder error unblocks a frame waiting on backpressure",
  { timeout: 2000 },
  async () => {
    const { fake, encoder } = await backpressuredEncoder()
    const pending = encoder.addFrame({}, 1)
    fake.fail(new Error("encoder died"))

    await assert.rejects(pending, /encoder died/)
  },
)

test(
  "cancelling unblocks a frame waiting on backpressure",
  { timeout: 2000 },
  async () => {
    const { encoder } = await backpressuredEncoder()
    const pending = encoder.addFrame({}, 1)
    encoder.abort()

    await assert.rejects(pending, /Render cancelled/)
  },
)

test(
  "a drained queue lets the next frame through",
  { timeout: 2000 },
  async () => {
    const { fake, encoder } = await backpressuredEncoder()
    const pending = encoder.addFrame({}, 1)
    setTimeout(() => fake.drain(), 0)

    await pending
  },
)
