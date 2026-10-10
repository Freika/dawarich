import { createBaseLayers } from "../layers/tile_layers.js"
import { createTileFreshness } from "../data/tile_freshness.js"
import { readRouteSnapshot } from "../data/route_snapshot.js"
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
  const freshness = createTileFreshness()
  let layers
  const config = JSON.parse(element.dataset.mapConfig ?? "{}")
  const owner = createMapRuntime({
    element,
    config,
    reader,
    loadLibrary,
    loadStyle,
    transformRequest: freshness.transformRequest,
    attach:
      attach ??
      (({ map, config, lifetime }) => {
        layers = createBaseLayers({
          map,
          config,
          freshness,
          onError: (code) => pushEvent("map:failed", { code }),
        })
        lifetime.own(() => layers.destroy())
        return new Promise((resolve) => {
          const ready = () => {
            layers.mount()
            resolve(() => map.off("load", ready))
          }
          if (map.loaded()) ready()
          else {
            map.once("load", ready)
            lifetime.own(() => map.off("load", ready))
          }
        })
      }),
    refresh: refresh ?? (({ config }) => layers?.update(config)),
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
    readSnapshot: (state, options) => readRouteSnapshot(reader, state, options),
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
