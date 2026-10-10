import { ArrayBufferTarget, Muxer } from "mp4-muxer"
import { pickSupportedCodec } from "./codec.js"

const KEYFRAME_INTERVAL_SEC = 2
const MAX_ENCODE_QUEUE = 8

export const renderCancelled = () =>
  new DOMException("Render cancelled", "AbortError")

const browser = () => ({
  VideoEncoder: globalThis.VideoEncoder,
  VideoFrame: globalThis.VideoFrame,
  OffscreenCanvas: globalThis.OffscreenCanvas,
  document: globalThis.document,
  Muxer,
  ArrayBufferTarget,
})

export function isVideoExportSupported(runtime = browser()) {
  return (
    typeof runtime.VideoEncoder === "function" &&
    typeof runtime.VideoFrame === "function"
  )
}

export async function probeVideoEncoderConfig(config, runtime = browser()) {
  let encoder = null
  let frame = null
  let encodeError = null

  try {
    const canvas =
      typeof runtime.OffscreenCanvas === "function"
        ? new runtime.OffscreenCanvas(config.width, config.height)
        : Object.assign(runtime.document.createElement("canvas"), {
            width: config.width,
            height: config.height,
          })
    canvas.getContext("2d")
    encoder = new runtime.VideoEncoder({
      output: () => {},
      error: (error) => {
        encodeError = error
      },
    })
    encoder.configure(config)
    frame = new runtime.VideoFrame(canvas, { timestamp: 0 })
    encoder.encode(frame, { keyFrame: true })
    await encoder.flush()
    return !encodeError
  } catch {
    return false
  } finally {
    frame?.close()
    try {
      if (encoder?.state !== "closed") encoder?.close()
    } catch {}
  }
}

export async function createMp4Encoder({
  width,
  height,
  fps,
  signal,
  runtime: given = {},
}) {
  const runtime = { ...browser(), ...given }
  if (!isVideoExportSupported(runtime)) return null
  if (signal?.aborted) throw renderCancelled()

  const pickCodec =
    runtime.pickCodec ??
    ((options) =>
      pickSupportedCodec({
        ...options,
        isConfigSupported: (config) =>
          runtime.VideoEncoder.isConfigSupported(config),
        probeConfig: (config) => probeVideoEncoderConfig(config, runtime),
      }))
  const picked = await pickCodec({ width, height, fps })
  if (!picked) return null
  if (signal?.aborted) throw renderCancelled()

  const target = new runtime.ArrayBufferTarget()
  const muxer = new runtime.Muxer({
    target,
    video: { codec: picked.muxerCodec, width, height, frameRate: fps },
    fastStart: "in-memory",
    firstTimestampBehavior: "offset",
  })

  let encodeError = null
  let aborted = false
  const parked = new Set()
  const wake = () => {
    for (const resume of [...parked]) resume()
  }
  const park = (subscribe) =>
    new Promise((resolve) => {
      const resume = () => {
        parked.delete(resume)
        unsubscribe?.()
        resolve()
      }
      parked.add(resume)
      const unsubscribe = subscribe(resume)
    })

  const encoder = new runtime.VideoEncoder({
    output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
    error: (error) => {
      encodeError = error
      wake()
    },
  })
  encoder.configure(picked.config)

  const keyframeEvery = Math.max(1, Math.round(fps * KEYFRAME_INTERVAL_SEC))
  const frameMicros = Math.round(1e6 / fps)
  const settle = () => {
    if (encodeError) throw encodeError
    if (aborted) throw renderCancelled()
  }

  function abort() {
    aborted = true
    signal?.removeEventListener("abort", abort)
    wake()
    try {
      if (encoder.state !== "closed") encoder.close()
    } catch {}
  }
  signal?.addEventListener("abort", abort, { once: true })

  return {
    codec: picked.config.codec,

    async addFrame(canvas, frameIndex) {
      settle()
      const frame = new runtime.VideoFrame(canvas, {
        timestamp: frameIndex * frameMicros,
        duration: frameMicros,
      })
      try {
        encoder.encode(frame, { keyFrame: frameIndex % keyframeEvery === 0 })
      } finally {
        frame.close()
      }
      while (
        encoder.encodeQueueSize > MAX_ENCODE_QUEUE &&
        !encodeError &&
        !aborted
      ) {
        await park((resume) => {
          encoder.addEventListener("dequeue", resume, { once: true })
          return () => encoder.removeEventListener("dequeue", resume)
        })
      }
      settle()
    },

    async finalize() {
      settle()
      let flushError = null
      await Promise.race([
        encoder.flush().catch((error) => {
          flushError = error
        }),
        park(() => null),
      ])
      wake()
      settle()
      if (flushError) throw flushError
      signal?.removeEventListener("abort", abort)
      encoder.close()
      muxer.finalize()
      return new Blob([target.buffer], { type: "video/mp4" })
    },

    abort,
  }
}
