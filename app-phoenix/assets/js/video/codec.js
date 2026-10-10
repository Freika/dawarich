import { waitForEncoder } from "./wait.js"

const CODEC_CANDIDATES = [
  { codec: "avc1.640028", muxerCodec: "avc" },
  { codec: "avc1.4d0028", muxerCodec: "avc" },
  { codec: "vp09.00.40.08", muxerCodec: "vp9" },
  { codec: "av01.0.08M.08", muxerCodec: "av1" },
]

const MIN_BITRATE = 4_000_000
const MAX_BITRATE = 16_000_000
const BITS_PER_PIXEL_PER_FRAME = 0.15

export function chooseBitrate(width, height, fps) {
  const raw = width * height * fps * BITS_PER_PIXEL_PER_FRAME
  return Math.round(Math.max(MIN_BITRATE, Math.min(MAX_BITRATE, raw)))
}

export async function pickSupportedCodec({
  width,
  height,
  fps,
  isConfigSupported,
  probeConfig,
  signal,
  timeoutMs,
  timers,
}) {
  const bitrate = chooseBitrate(width, height, fps)
  for (const candidate of CODEC_CANDIDATES) {
    const config = {
      codec: candidate.codec,
      width,
      height,
      framerate: fps,
      bitrate,
      ...(candidate.muxerCodec === "avc" ? { avc: { format: "avc" } } : {}),
    }
    try {
      const result = await waitForEncoder(() => isConfigSupported(config), {
        signal,
        timeoutMs,
        timers,
      })
      if (!result?.supported) continue
      if (
        probeConfig &&
        !(await waitForEncoder(() => probeConfig(config), {
          signal,
          timeoutMs,
          timers,
        }))
      )
        continue
      return { muxerCodec: candidate.muxerCodec, config }
    } catch (error) {
      if (error.name === "AbortError" || error.name === "TimeoutError")
        throw error
    }
  }
  return null
}
