import { createReader } from "../data/reader.js"
import { readRouteSnapshot } from "../data/route_snapshot.js"
import { createStudioSource } from "../data/studio_source.js"
import { createTileFreshness } from "../data/tile_freshness.js"
import { createBaseLayers } from "../layers/tile_layers.js"
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
  let density
  let photos
  let photoKey
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
        lifetime.own(() => density?.destroy())
        lifetime.own(() => photos?.remove())
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
    refresh:
      refresh ??
      (async ({ map, config, operation, signal }) => {
        layers?.update(config)
        if (
          !density &&
          (config.fogEnabled || config.hexagonsEnabled || config.scratchEnabled)
        ) {
          const [module, library] = await operation.wait(
            Promise.all([
              import("../layers/density.js"),
              loadLibrary({ signal }),
            ]),
          )
          operation.check()
          density = module.createDensityLayers({
            map,
            reader,
            library,
            pointsLayer: layers?.points,
            onError: (code) => pushEvent("map:failed", { code }),
            onProgress: (receipt) =>
              element.dispatchEvent(
                new CustomEvent("map:progress", { detail: receipt }),
              ),
            formatCount: (count) =>
              (owner.config.hexagonLabel ?? "{count} points").replace(
                "{count}",
                new Intl.NumberFormat(owner.config.locale ?? "en").format(
                  count,
                ),
              ),
          })
        }
        if (density) await operation.wait(density.update(config, { signal }))
        if (!config.photosEnabled) {
          photos?.remove()
          photos = null
          photoKey = null
        } else {
          const desired = JSON.stringify([
            config.range,
            config.epoch,
            config.locale,
          ])
          if (photoKey !== desired || !photos) {
            const [module, library] = await operation.wait(
              Promise.all([
                import("../layers/photos.js"),
                loadLibrary({ signal }),
              ]),
            )
            operation.check()
            photos?.remove()
            photos = new module.PhotosLayer(map, {
              reader,
              library,
              timezone: config.range.timezone,
              labels: config.photoLabels,
              onError: (code) => pushEvent("map:failed", { code }),
            })
            photos.add()
            const status = await operation.wait(
              photos.load(config.range, { signal }),
            )
            operation.check()
            if (status !== "ready") throw new Error("Photos unavailable")
            photoKey = desired
          }
        }
      }),
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
