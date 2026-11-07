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
const avccSource = (
  await readFile(
    new URL("../../app/javascript/video_studio/avcc.js", import.meta.url),
    "utf8",
  )
).replace(/^export /gm, "")
const prelude = `
${avccSource}
class ArrayBufferTarget { constructor() { this.buffer = new ArrayBuffer(8) } }
class Muxer {
  addVideoChunk(chunk, meta) { globalThis.__muxerCalls.push({ chunk, meta }) }
  finalize() {}
}
globalThis.__muxerCalls = []
async function pickSupportedCodec() {
  return { config: { codec: "avc1.42001f" }, muxerCodec: "avc" }
}
`
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(prelude + withoutImports).toString("base64")}`
const { createMp4Encoder, probeVideoEncoderConfig } = await import(moduleUrl)

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
  function FakeVideoEncoder({ output, error }) {
    raiseError = error
    codec.output = output
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

test("runtime probe rejects a codec whose first encode throws", async () => {
  let encoderClosed = false
  let frameClosed = false

  globalThis.OffscreenCanvas = class {
    initialized = false

    getContext() {
      this.initialized = true
    }
  }
  globalThis.VideoFrame = class {
    constructor(source) {
      if (!source.initialized) throw new DOMException("Invalid source state")
    }

    close() {
      frameClosed = true
    }
  }
  globalThis.VideoEncoder = class {
    state = "configured"

    configure() {}

    encode() {
      throw new DOMException(
        "The given encoding is not supported.",
        "NotSupportedError",
      )
    }

    async flush() {}

    close() {
      this.state = "closed"
      encoderClosed = true
    }
  }

  const supported = await probeVideoEncoderConfig({ width: 8, height: 8 })

  assert.equal(supported, false)
  assert.equal(frameClosed, true)
  assert.equal(encoderClosed, true)
})

const fromHex = (value) =>
  Uint8Array.from(value.trim().split(/\s+/), (byte) =>
    Number.parseInt(byte, 16),
  )
const toHex = (bytes) =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(" ")

const BROKEN_AVCC = fromHex(`
  01 64 00 28 03 01 00 1b
  67 67 64 00 28 ac 2c ac 04 40 3c 79 78
  40 00 00 03 00 40 00 00 0f 03 68 22 11 4e
  01 00 05 68 68 ce 3c 30
`)
const FIXED_AVCC = fromHex(`
  01 64 00 28 ff e1 00 1a
  67 64 00 28 ac 2c ac 04 40 3c 79 78
  40 00 00 03 00 40 00 00 0f 03 68 22 11 4e
  01 00 04 68 ce 3c 30
`)

test("repairs Firefox's duplicated avcC headers before muxing", async () => {
  globalThis.__muxerCalls.length = 0
  const { fake } = await backpressuredEncoder()

  fake.codec.output({}, { decoderConfig: { description: BROKEN_AVCC } })

  assert.equal(globalThis.__muxerCalls.length, 1)
  assert.equal(
    toHex(globalThis.__muxerCalls[0].meta.decoderConfig.description),
    toHex(FIXED_AVCC),
  )
})

test("passes a canonical avcC through untouched", async () => {
  globalThis.__muxerCalls.length = 0
  const { fake } = await backpressuredEncoder()

  fake.codec.output({}, { decoderConfig: { description: FIXED_AVCC } })

  assert.equal(globalThis.__muxerCalls.length, 1)
  assert.equal(
    globalThis.__muxerCalls[0].meta.decoderConfig.description,
    FIXED_AVCC,
  )
})
