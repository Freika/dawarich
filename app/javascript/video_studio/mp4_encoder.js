// WebCodecs → mp4-muxer wrapper. Encodes composited canvas frames into an
// in-memory MP4. Browser-only: callers gate on isVideoExportSupported().
import { ArrayBufferTarget, Muxer } from "mp4-muxer"
import { pickSupportedCodec } from "video_studio/codec_negotiation"

const KEYFRAME_INTERVAL_SEC = 2
const MAX_ENCODE_QUEUE = 8

export function isVideoExportSupported() {
  return typeof VideoEncoder === "function" && typeof VideoFrame === "function"
}

export async function createMp4Encoder({ width, height, fps }) {
  if (!isVideoExportSupported()) return null

  const picked = await pickSupportedCodec({
    width,
    height,
    fps,
    isConfigSupported: (config) => VideoEncoder.isConfigSupported(config),
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
  const encoder = new VideoEncoder({
    output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
    error: (error) => {
      encodeError = error
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
      while (encoder.encodeQueueSize > MAX_ENCODE_QUEUE && !encodeError) {
        await new Promise((resolve) => {
          encoder.addEventListener("dequeue", resolve, { once: true })
        })
      }
    },

    async finalize() {
      await encoder.flush()
      encoder.close()
      if (encodeError) throw encodeError
      muxer.finalize()
      return new Blob([target.buffer], { type: "video/mp4" })
    },

    abort() {
      try {
        if (encoder.state !== "closed") encoder.close()
      } catch {
        // Already closed while tearing down — nothing to release.
      }
    },
  }
}
