import { createReader } from "../data/reader.js"
import { readRouteSnapshot } from "../data/route_snapshot.js"
import { createStudioSource } from "../data/studio_source.js"
import { createTileFreshness } from "../data/tile_freshness.js"
import { createHostEditing } from "../edit/host.js"
import { createBaseLayers } from "../layers/tile_layers.js"
import { installHostReplay } from "../replay/host.js"
import { createHostSelection } from "../selection/host.js"
import { fetchStyle } from "../style/load_style.js"
import { createEnrichmentTool } from "../ui/enrichment.js"
import { createHostSearch } from "../ui/host_search.js"
import { createHostSettings } from "../ui/host_settings.js"
import { createHostTimeline } from "../ui/host_timeline.js"
import { createHostTools } from "../ui/host_tools.js"
import { createHostVisits } from "../ui/host_visits.js"
import { createRangeRequests } from "../ui/navigation.js"
import { installStudios } from "../ui/studios.js"
import { createHostAuxLayers } from "./aux_layers.js"
import { createMapRuntime } from "./create_map.js"
import { createViewportFit } from "./viewport_fit.js"
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
  const fit = createViewportFit(reader, element)
  let library
  let layers
  let editing
  let enrichment
  let timeline
  let density
  let aux
  let entities
  const config = JSON.parse(element.dataset.mapConfig ?? "{}")
  const owner = createMapRuntime({
    element,
    config,
    reader,
    loadLibrary: async (options) => {
      library = await loadLibrary(options)
      return library
    },
    loadStyle,
    transformRequest: freshness.transformRequest,
    attach:
      attach ??
      (({ map, config, lifetime }) => {
        installStudios({ element, owner, lifetime })
        installHostReplay({
          onActive: (active) =>
            active ? aux?.photos?.hide() : aux?.photos?.show(),
          library,
          reader,
          owner,
          map,
          lifetime,
          root: element.closest?.("[data-native-map-root]"),
        })
        owner.settings = createHostSettings({
          map,
          loadStyle,
          lifetime,
          getConfig: () => owner.config,
          update: (next) => owner.update(next),
          onError: (code) => pushEvent("map:failed", { code }),
        })
        enrichment = createEnrichmentTool({
          map,
          pushEvent,
          createPopup: () => null,
        })
        lifetime.own(enrichment.destroy)
        owner.search = createHostSearch({
          map,
          root: element.closest?.("[data-native-map-root]"),
          reader,
          lifetime,
          document: element.ownerDocument,
          pushEvent,
          getConfig: () => owner.config,
        })
        owner.selection = createHostSelection({
          map,
          root: element.closest?.("[data-native-map-root]"),
          reader,
          pushEvent,
          lifetime,
          getConfig: () => owner.config,
        })
        owner.timeline = timeline = createHostTimeline({
          library,
          pushEvent,
          getConfig: () => owner.config,
          replay: () => owner.replay,
          blocked: () =>
            owner.config.editEnabled ||
            owner.selection.state.active ||
            Boolean(
              element
                .closest?.("[data-native-map-root]")
                ?.querySelector("[data-map-tool-status]")?.textContent,
            ),
          map,
          root: element.closest?.("[data-native-map-root]"),
          reader,
          lifetime,
        })
        owner.visits = createHostVisits({
          map,
          reader,
          lifetime,
          root: element.closest?.("[data-native-map-root]"),
          getConfig: () => owner.config,
          entities: () => entities,
        })
        createHostTools({
          map,
          root: element.closest?.("[data-native-map-root]"),
          pushEvent,
          lifetime,
        })
        layers = createBaseLayers({
          map,
          config,
          freshness,
          onError: (code) => pushEvent("map:failed", { code }),
        })
        lifetime.own(() => layers.destroy())
        editing = createHostEditing({
          map,
          reader,
          pushEvent,
          lifetime,
          getConfig: () => owner.config,
          layers,
          document: element.ownerDocument,
          root: element.closest?.("[data-native-map-root]"),
        })
        lifetime.own(() => density?.destroy())
        aux = createHostAuxLayers({
          map,
          reader,
          library,
          root: element.closest?.("[data-native-map-root]"),
          onError: (code) => pushEvent("map:failed", { code }),
          replayActive: () => owner.replay?.active,
        })
        lifetime.own(() => aux.destroy())
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
        await fit({ map, config, operation, signal })
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
        if (aux) await operation.wait(aux.update(config, { operation, signal }))
      }),
    events: {
      refreshed(receipt) {
        pushEvent("map:ready", receipt)
      },
      error(receipt) {
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
  Object.defineProperty(owner, "pointEditing", {
    get: () => editing?.transport,
  })
  Object.defineProperty(owner, "editor", { get: () => editing?.editor })
  Object.defineProperty(owner, "entityLayers", { get: () => entities })
  Object.defineProperty(owner, "photoLayer", { get: () => aux?.photos })
  owner.visitsFilter = (filter) =>
    owner.update({ ...owner.config, visitFilter: filter })
  owner.layer = ({ layer, enabled }) => {
    if (!["places", "visits", "areas", "anomalies"].includes(layer)) return
    return owner.update({
      ...owner.config,
      [`${layer}Enabled`]: enabled === true,
    })
  }
  const reconnect = owner.reconnect
  owner.reconnect = async () => {
    const state = await reconnect.call(owner)
    if (state === "ready") {
      layers?.points.refresh()
      layers?.tracks.refresh()
    }
    return state
  }
  const update = owner.update
  owner.update = (config) => {
    if (config.revision !== owner.config.revision) {
      enrichment?.clear()
      owner.selection?.cancel()
    }
    aux?.clear(config)
    timeline?.config(config)
    owner.visits?.config(config)
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
