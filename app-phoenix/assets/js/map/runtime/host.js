import { createReader } from "../data/reader.js"
import { createStudioSource } from "../data/studio_source.js"
import { createMapRuntime } from "./create_map.js"

export { createMapRuntime }

export function mountHost({
  element,
  pushEvent,
  reader = createReader(),
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  loadStyle = fetchStyle,
  attach,
  refresh,
}) {
  const config = JSON.parse(element.dataset.mapConfig ?? "{}")
  const owner = createMapRuntime({
    element,
    config,
    reader,
    loadLibrary,
    loadStyle,
    attach,
    refresh,
    events: {
      refreshed(receipt) {
        element.dataset.mapState = "ready"
        pushEvent("map:ready", receipt)
      },
      error(receipt) {
        element.dataset.mapState = "failed"
        pushEvent("map:failed", receipt)
      },
    },
  })
  owner.source = createStudioSource({
    getState: () => owner.config,
    readSnapshot: async (state, options) => ({
      points: await reader.pages(
        "points",
        {
          start_at: state.range.startAt,
          end_at: state.range.endAt,
          import_id: state.range.importId,
        },
        { signal: options.signal },
      ),
    }),
    applyDates: (range) =>
      new Promise((resolve) => pushEvent("map:range", range, resolve)),
  })
  const dispose = owner.destroy
  owner.destroy = () => {
    owner.source.destroy()
    dispose()
  }
  return owner
}

async function fetchStyle(config, { signal }) {
  const response = await fetch(
    config.styleUrl ?? "/maps_maplibre/styles/light.json",
    { signal, credentials: "same-origin" },
  )
  if (!response.ok) throw new Error("Map style unavailable")
  return response.json()
}
