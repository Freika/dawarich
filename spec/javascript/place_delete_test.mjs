import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function setup({ confirmed = true, ok = true } = {}) {
  const calls = []
  const source = (
    await readFile(
      new URL(
        "../../app/javascript/maps_maplibre/components/place_actions.js",
        import.meta.url,
      ),
      "utf8",
    )
  ).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const { deletePlace } = await import(
    `data:text/javascript;base64,${Buffer.from(`export let dependencies; export const setup = (value) => dependencies = value;
    const translate = (key) => key;
    const confirm = (message) => dependencies.confirm(message);
    const fetch = (...args) => dependencies.fetch(...args);
    const Toast = {success: (message) => dependencies.success(message), error: (message) => dependencies.error(message)};
    ${source}`).toString("base64")}`
  ).then((module) => {
    module.setup({
      confirm: (message) => {
        calls.push(["confirm", message])
        return confirmed
      },
      fetch: async (...args) => {
        calls.push(["fetch", ...args])
        return { ok }
      },
      success: (message) => calls.push(["success", message]),
      error: (message) => calls.push(["error", message]),
    })
    return module
  })
  const layer = {
    data: {
      type: "FeatureCollection",
      features: [42, "42", 7].map((id) => ({ properties: { id } })),
    },
    update(data) {
      this.data = data
      calls.push(["update"])
    },
  }
  const controller = {
    apiKeyValue: "test-key",
    layerManager: { getLayer: () => layer },
    closeInfo: () => calls.push(["close"]),
    placesManager: {
      _refreshPrivacyZones: async () => calls.push(["privacy"]),
    },
  }
  return { run: () => deletePlace(controller, "42"), calls, layer }
}

test("deleting a place authenticates then removes both features closes info toasts and refreshes privacy", async () => {
  const { run, calls, layer } = await setup()
  await run()
  assert.deepEqual(calls, [
    ["confirm", "places.confirm_delete"],
    [
      "fetch",
      "/api/v1/places/42",
      {
        method: "DELETE",
        headers: {
          Authorization: "Bearer test-key",
          "Content-Type": "application/json",
        },
      },
    ],
    ["update"],
    ["close"],
    ["success", "messages.place_deleted_successfully"],
    ["privacy"],
  ])
  assert.deepEqual(
    layer.data.features.map((feature) => feature.properties.id),
    [7],
  )
})

test("cancelling place deletion preserves the layer and makes no request", async () => {
  const { run, calls, layer } = await setup({ confirmed: false })
  await run()
  assert.deepEqual(calls, [["confirm", "places.confirm_delete"]])
  assert.equal(layer.data.features.length, 3)
})

test("failed place deletion preserves the layer and panel and shows an error", async () => {
  const { run, calls, layer } = await setup({ ok: false })
  await run()
  assert.equal(layer.data.features.length, 3)
  assert.deepEqual(
    calls.map(([kind]) => kind),
    ["confirm", "fetch", "error"],
  )
  assert.equal(calls.at(-1)[1], "messages.failed_to_delete_place")
})
