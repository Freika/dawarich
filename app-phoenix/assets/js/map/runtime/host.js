import { createHostSettings } from "../ui/host_settings.js"
import { createHostEditing } from "../edit/host.js"
import { createEnrichmentTool } from "../ui/enrichment.js"
import { createHostSearch } from "../ui/host_search.js"
import { createReader } from "../data/reader.js"
import { readRouteSnapshot } from "../data/route_snapshot.js"
import { createStudioSource } from "../data/studio_source.js"
import { createTileFreshness } from "../data/tile_freshness.js"
import { createBaseLayers } from "../layers/tile_layers.js"
import { createHostTimeline } from "../ui/host_timeline.js"
import { createHostTools } from "../ui/host_tools.js"
import { createRangeRequests } from "../ui/navigation.js"
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
  const requests = createRangeRequests({ pushEvent })
  const freshness = createTileFreshness()
  let layers
  let editing
  let enrichment
  let timeline
  let density
  let photos
  let photoKey
  let entities
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
        owner.settings = createHostSettings({ map, loadStyle, lifetime, getConfig: () => owner.config, update: next => owner.update(next), onError: code => pushEvent("map:failed", {code}) })
        enrichment = createEnrichmentTool({ map, pushEvent, createPopup: () => null })
        lifetime.own(enrichment.destroy)
        createHostSearch({map, root: element.closest?.("#native-map-page"), reader, lifetime, document: element.ownerDocument})
        timeline = createHostTimeline({ map, root: element.closest?.("#native-map-page"), reader, lifetime })
        createHostTools({ map, root: element.closest?.("#native-map-page"), pushEvent, lifetime })
        layers = createBaseLayers({
          map,
          config,
          freshness,
          onError: (code) => pushEvent("map:failed", { code }),
        })
        lifetime.own(() => layers.destroy())
        editing = createHostEditing({ map, reader, pushEvent, lifetime, getConfig: () => owner.config, layers, document: element.ownerDocument })
        lifetime.own(() => density?.destroy())
        lifetime.own(() => photos?.remove())
        lifetime.own(() => entities?.destroy())
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
        if (
          !entities &&
          (config.visitsEnabled ||
            config.placesEnabled ||
            config.areasEnabled ||
            config.anomaliesEnabled)
        ) {
          const [module, library] = await operation.wait(
            Promise.all([
              import("../layers/entities.js"),
              loadLibrary({ signal }),
            ]),
          )
          operation.check()
          entities = module.createEntityLayers({
            map,
            reader,
            library,
            onSelect: (receipt) => pushEvent("map:select", receipt),
            onError: (code) => pushEvent("map:failed", { code }),
          })
        }
        if (entities) await operation.wait(entities.update(config, { signal }))
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
    applyDates: requests.applyDates,
  })
  Object.defineProperty(owner, "enrichment", { get: () => enrichment })
  Object.defineProperty(owner, "editor", { get: () => editing?.editor })
  Object.defineProperty(owner, "entityLayers", { get: () => entities })
  const update = owner.update
  owner.update = (config) => {
    if (config.revision !== owner.config.revision) enrichment?.clear()
    timeline?.config(config)
    editing?.config(config)
    const updating = update.call(owner, config)
    requests.config(config)
    return updating
  }
  requests.config(config)
  const dispose = owner.destroy
  owner.destroy = () => {
    requests.destroy()
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
