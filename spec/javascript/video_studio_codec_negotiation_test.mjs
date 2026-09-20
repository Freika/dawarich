import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/video_studio/codec_negotiation.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { pickSupportedCodec } = await import(moduleUrl)

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
