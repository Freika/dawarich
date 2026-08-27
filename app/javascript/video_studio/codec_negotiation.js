// WebCodecs codec negotiation, decoupled from the browser: the probe function
// is injected so the preference order stays testable. H.264 first (plays
// everywhere), then VP9 and AV1 — all three mux into MP4 via mp4-muxer.
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
      const result = await isConfigSupported(config)
      if (result?.supported) return { muxerCodec: candidate.muxerCodec, config }
    } catch {
      // An unknown codec string throws in some browsers — same as unsupported.
    }
  }
  return null
}
