import assert from "node:assert/strict"
import test from "node:test"
import {
  chooseBitrate,
  pickSupportedCodec,
} from "../../app-phoenix/assets/js/video/codec.js"
import {
  createMp4Encoder,
  isVideoExportSupported,
  probeVideoEncoderConfig,
} from "../../app-phoenix/assets/js/video/mp4_encoder.js"

class ArrayBufferTarget {
  constructor() {
    this.buffer = new ArrayBuffer(8)
  }
}
const muxers = []
class Muxer {
  constructor(options) {
    this.options = options
    this.chunks = []
    muxers.push(this)
  }
  addVideoChunk(chunk) {
    this.chunks.push(chunk)
  }
  finalize() {
    this.finalized = true
  }
}
const runtime = (overrides = {}) => ({
  VideoEncoder: globalThis.VideoEncoder,
  VideoFrame: globalThis.VideoFrame,
  Muxer,
  ArrayBufferTarget,
  pickCodec: async () => ({
    config: { codec: "avc1.42001f" },
    muxerCodec: "avc",
  }),
  ...overrides,
})

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
  const encoder = await createMp4Encoder({
    width: 8,
    height: 8,
    fps: 30,
    runtime: runtime(),
  })
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

  const supported = await probeVideoEncoderConfig(
    { width: 8, height: 8 },
    {
      VideoEncoder: globalThis.VideoEncoder,
      VideoFrame: globalThis.VideoFrame,
      OffscreenCanvas: globalThis.OffscreenCanvas,
    },
  )

  assert.equal(supported, false)
  assert.equal(frameClosed, true)
  assert.equal(encoderClosed, true)
})

test("falls through when a reported codec fails the runtime probe", async () => {
  const probed = []
  const picked = await pickSupportedCodec({
    width: 1920,
    height: 1080,
    fps: 30,
    isConfigSupported: async () => ({ supported: true }),
    probeConfig: async (config) => {
      probed.push(config.codec)
      if (config.codec.startsWith("avc1")) {
        throw new DOMException(
          "The given encoding is not supported.",
          "NotSupportedError",
        )
      }
      return true
    },
  })

  assert.equal(picked.config.codec, "vp09.00.40.08")
  assert.deepEqual(probed, ["avc1.640028", "avc1.4d0028", "vp09.00.40.08"])
})

test("returns null when every reported codec fails the runtime probe", async () => {
  const picked = await pickSupportedCodec({
    width: 1080,
    height: 1920,
    fps: 30,
    isConfigSupported: async () => ({ supported: true }),
    probeConfig: async () => false,
  })

  assert.equal(picked, null)
})

test(
  "abort wakes encoder backpressure and closes frames",
  { timeout: 2000 },
  async () => {
    const fake = fakeVideoEncoder()
    const frames = []
    globalThis.VideoFrame = class {
      constructor() {
        this.closed = false
        frames.push(this)
      }
      close() {
        this.closed = true
      }
    }
    const controller = new AbortController()
    const encoder = await createMp4Encoder({
      width: 8,
      height: 8,
      fps: 30,
      signal: controller.signal,
      runtime: runtime(),
    })
    fake.codec.encodeQueueSize = 100
    const parked = encoder.addFrame({}, 1)
    controller.abort()
    await assert.rejects(parked, {
      name: "AbortError",
      message: /Render cancelled/,
    })
    assert.equal(fake.codec.state, "closed")
    assert.ok(frames.every((frame) => frame.closed))

    const throwing = fakeVideoEncoder()
    globalThis.VideoFrame = class {
      constructor() {
        frames.push(this)
      }
      close() {
        this.closed = true
      }
    }
    throwing.codec.encode = () => {
      throw new DOMException("bad frame", "EncodingError")
    }
    const second = await createMp4Encoder({
      width: 8,
      height: 8,
      fps: 30,
      runtime: runtime(),
    })
    await assert.rejects(second.addFrame({}, 0), /bad frame/)
    assert.equal(frames.at(-1).closed, true)
  },
)

test("abort wakes a parked finalize", { timeout: 2000 }, async () => {
  const fake = fakeVideoEncoder()
  fake.codec.flush = () => new Promise(() => {})
  const encoder = await createMp4Encoder({
    width: 8,
    height: 8,
    fps: 30,
    runtime: runtime(),
  })
  const finishing = encoder.finalize()
  encoder.abort()
  await assert.rejects(finishing, { name: "AbortError" })
})

test("runtime probe rejects encode failure", async () => {
  const closed = []
  const supported = await probeVideoEncoderConfig(
    { width: 8, height: 8 },
    {
      OffscreenCanvas: class {
        getContext() {}
      },
      VideoFrame: class {
        close() {
          closed.push("frame")
        }
      },
      VideoEncoder: class {
        constructor({ error }) {
          this.error = error
          this.state = "configured"
        }
        configure() {}
        encode() {
          this.error(new DOMException("encoder failed", "EncodingError"))
        }
        async flush() {}
        close() {
          this.state = "closed"
          closed.push("encoder")
        }
      },
    },
  )
  assert.equal(supported, false)
  assert.deepEqual(closed.sort(), ["encoder", "frame"])
})

test("unsupported codec refuses without map allocation", async () => {
  muxers.length = 0
  const missing = await createMp4Encoder({
    width: 8,
    height: 8,
    fps: 30,
    runtime: runtime({ VideoEncoder: undefined }),
  })
  assert.equal(missing, null)
  const none = await createMp4Encoder({
    width: 8,
    height: 8,
    fps: 30,
    runtime: runtime({
      VideoEncoder: class {},
      VideoFrame: class {},
      pickCodec: async () => null,
    }),
  })
  assert.equal(none, null)
  assert.equal(muxers.length, 0)
  assert.equal(isVideoExportSupported({}), false)
})

test("finalize muxes the encoded chunks into an MP4 blob", async () => {
  const fake = fakeVideoEncoder()
  muxers.length = 0
  const encoder = await createMp4Encoder({
    width: 1080,
    height: 1920,
    fps: 30,
    runtime: runtime(),
  })
  assert.deepEqual(muxers[0].options.video, {
    codec: "avc",
    width: 1080,
    height: 1920,
    frameRate: 30,
  })
  assert.equal(muxers[0].options.fastStart, "in-memory")
  await encoder.addFrame({}, 0)
  const blob = await encoder.finalize()
  assert.equal(blob.type, "video/mp4")
  assert.equal(muxers[0].finalized, true)
  assert.equal(fake.codec.state, "closed")
  assert.equal(chooseBitrate(1080, 1920, 30), 9_331_200)
  assert.equal(chooseBitrate(8, 8, 30), 4_000_000)
})
