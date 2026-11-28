// WebCodecs → mp4-muxer wrapper. Encodes composited canvas frames into an
// in-memory MP4. Browser-only: callers gate on isVideoExportSupported().
import { ArrayBufferTarget, Muxer } from "mp4-muxer"
import { pickSupportedCodec } from "video_studio/codec_negotiation"

const KEYFRAME_INTERVAL_SEC = 2
const MAX_ENCODE_QUEUE = 8

export function isVideoExportSupported() {
  return typeof VideoEncoder === "function" && typeof VideoFrame === "function"
}

export async function probeVideoEncoderConfig(config) {
  let encoder = null
  let frame = null
  let encodeError = null

  try {
    const canvas =
      typeof OffscreenCanvas === "function"
        ? new OffscreenCanvas(config.width, config.height)
        : Object.assign(document.createElement("canvas"), {
            width: config.width,
            height: config.height,
          })

    canvas.getContext("2d")

    encoder = new VideoEncoder({
      output: () => {},
      error: (error) => {
        encodeError = error
      },
    })
    encoder.configure(config)
    frame = new VideoFrame(canvas, { timestamp: 0 })
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

// Decode times are the presentation times in sorted order, pulled back by the
// deepest reorder so no chunk is decoded after it is shown. Without B-frames
// the shift is zero and every composition offset is zero.
function muxInDecodeOrder(muxer, chunks) {
  const decodeTimes = chunks
    .map(({ chunk }) => chunk.timestamp)
    .sort((a, b) => a - b)
  const shift = chunks.reduce(
    (deepest, { chunk }, i) =>
      Math.max(deepest, decodeTimes[i] - chunk.timestamp),
    0,
  )
  chunks.forEach(({ chunk, meta }, i) => {
    const decodeTime = decodeTimes[i] - shift
    muxer.addVideoChunk(
      chunk,
      meta,
      chunk.timestamp,
      chunk.timestamp - decodeTime,
    )
  })
}

export async function createMp4Encoder({ width, height, fps }) {
  if (!isVideoExportSupported()) return null

  const picked = await pickSupportedCodec({
    width,
    height,
    fps,
    isConfigSupported: (config) => VideoEncoder.isConfigSupported(config),
    probeConfig: probeVideoEncoderConfig,
  })
  if (!picked) return null

  const target = new ArrayBufferTarget()
  const muxer = new Muxer({
    target,
    video: { codec: picked.muxerCodec, width, height, frameRate: fps },
    fastStart: "in-memory",
    firstTimestampBehavior: "offset",
  })

  let encodeError = null
  let aborted = false
  // Frames parked on backpressure wait for a "dequeue" that a dead or closed
  // encoder will never fire, so an error or a cancel has to wake them too.
  const parked = new Set()
  const wake = () => {
    for (const resume of [...parked]) resume()
  }

  // Firefox's H.264 encoder emits B-frames: chunks arrive in decode order but
  // carry presentation timestamps, which the muxer takes for decode times and
  // rejects as soon as one goes backwards. Collect them and mux at the end,
  // when the decode order is known. A 30 s clip stays within tens of MB.
  const chunks = []
  const encoder = new VideoEncoder({
    output: (chunk, meta) => chunks.push({ chunk, meta }),
    error: (error) => {
      encodeError =
        error.name === "QuotaExceededError"
          ? new Error(
              "The browser released the video encoder while this tab was in the background. Keep the tab visible during the export.",
            )
          : error
      wake()
    },
  })
  encoder.configure(picked.config)

  const keyframeEvery = Math.max(1, Math.round(fps * KEYFRAME_INTERVAL_SEC))
  const frameMicros = Math.round(1e6 / fps)

  return {
    codec: picked.config.codec,

    async addFrame(canvas, frameIndex) {
      if (encodeError) throw encodeError
      const frame = new VideoFrame(canvas, {
        timestamp: frameIndex * frameMicros,
        duration: frameMicros,
      })
      encoder.encode(frame, { keyFrame: frameIndex % keyframeEvery === 0 })
      frame.close()
      while (
        encoder.encodeQueueSize > MAX_ENCODE_QUEUE &&
        !encodeError &&
        !aborted
      ) {
        await new Promise((resolve) => {
          const resume = () => {
            parked.delete(resume)
            encoder.removeEventListener("dequeue", resume)
            resolve()
          }
          parked.add(resume)
          encoder.addEventListener("dequeue", resume, { once: true })
        })
      }
      if (encodeError) throw encodeError
      if (aborted) throw new Error("Render cancelled")
    },

    async finalize() {
      await encoder.flush()
      encoder.close()
      if (encodeError) throw encodeError
      muxInDecodeOrder(muxer, chunks)
      chunks.length = 0
      muxer.finalize()
      return new Blob([target.buffer], { type: "video/mp4" })
    },

    abort() {
      aborted = true
      wake()
      try {
        if (encoder.state !== "closed") encoder.close()
      } catch {
        // Already closed while tearing down — nothing to release.
      }
    },
  }
}
