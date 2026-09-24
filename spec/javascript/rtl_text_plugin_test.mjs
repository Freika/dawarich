import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/rtl_text_plugin.js",
    import.meta.url,
  ),
  "utf8",
)
const { registerRTLTextPlugin } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

test("registers the local worker plugin once across repeated map initializations", async () => {
  let status = "unavailable"
  const requests = []
  const maplibre = {
    getRTLTextPluginStatus: () => status,
    setRTLTextPlugin: async (...args) => {
      requests.push(args)
      status = "deferred"
    },
  }
  await registerRTLTextPlugin(maplibre, "/assets/rtl-digest.js")
  await registerRTLTextPlugin(maplibre, "/assets/rtl-digest.js")
  assert.deepEqual(requests, [["/assets/rtl-digest.js", true]])
})

for (const status of ["deferred", "loading", "loaded", "error"]) {
  test(`keeps an existing ${status} registration`, () => {
    registerRTLTextPlugin(
      {
        getRTLTextPluginStatus: () => status,
        setRTLTextPlugin: () => assert.fail("duplicate registration"),
      },
      "/assets/rtl.js",
    )
  })
}

test("registers after a different map requested RTL text", async () => {
  let registered = false
  await registerRTLTextPlugin(
    {
      getRTLTextPluginStatus: () => "requested",
      setRTLTextPlugin: async () => {
        registered = true
      },
    },
    "/assets/rtl.js",
  )
  assert.equal(registered, true)
})

test("contains asynchronous plugin loading failures", async (t) => {
  const warning = t.mock.method(console, "warn", () => {})
  await assert.doesNotReject(
    registerRTLTextPlugin(
      {
        getRTLTextPluginStatus: () => "unavailable",
        setRTLTextPlugin: async () => {
          throw new Error("offline")
        },
      },
      "/assets/rtl.js",
    ),
  )
  assert.equal(warning.mock.callCount(), 1)
})
