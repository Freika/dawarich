import { createReader } from "../data/reader.js"
import { cancelled } from "../data/request_scope.js"
import { readRouteSnapshot } from "../data/route_snapshot.js"
import { createStudioSource } from "../data/studio_source.js"
import { installHostReplay } from "../replay/host.js"
import { createMapRuntime } from "../runtime/create_map.js"
import { waitForStyle } from "../runtime/style_ready.js"
import { fetchStyle } from "../style/load_style.js"
import { installStudios } from "../ui/studios.js"
import { createTripLayers } from "./layers.js"
export function mountTrip({
  element,
  pushEvent,
  reader = createReader(),
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  loadStyle = fetchStyle,
  createLayers = createTripLayers,
}) {
  let library, layers, photos, loadedConfig
  const initial = JSON.parse(element.dataset.mapConfig ?? "{}")
  const owner = createMapRuntime({
    element,
    config: initial,
    reader,
    loadLibrary: async (options) => {
      library = await loadLibrary(options)
      return library
    },
    loadStyle,
    attach: ({ map, config, lifetime }) =>
      waitForStyle(map, lifetime).then(() => {
        const ready = () => {
          installStudios({ element, owner, lifetime })
          installHostReplay({
            onActive: (active) => (active ? photos?.hide() : photos?.show()),
            library,
            reader,
            owner,
            map,
            lifetime,
            root: element.closest?.("[data-native-map-root]"),
          })
          layers = createLayers({
            map,
            library,
            labels: config.entityLabels,
            onDay: (receipt) => pushEvent("trip:day", receipt),
          })
          lifetime.own(() => layers.destroy())
          lifetime.own(() => photos?.remove())
        }
        ready()
      }),
    refresh: async ({ map, config, operation, signal }) => {
      const { data } = await operation.wait(
        reader.read("trip", { id: config.tripId }, { signal }),
      )
      operation.check()
      loadedConfig = {
        ...config,
        ...data.config,
        revision: config.revision,
        flightsEnabled: config.flightsEnabled ?? data.config.flightsEnabled,
        photosEnabled: config.photosEnabled ?? data.config.photosEnabled,
        planEnabled: config.planEnabled ?? data.config.planEnabled,
      }
      layers.update(data, { points: [] }, loadedConfig)
      const snapshot = await operation.wait(
        readRouteSnapshot(reader, loadedConfig, {
          purpose: "poster",
          signal,
          deviceWindows: data.deviceWindows,
          routeOptions: data.config.routeOptions,
        }),
      )
      operation.check()
      layers.update(data, snapshot, loadedConfig)
      photos?.remove()
      photos = null
      if (loadedConfig.photosEnabled) {
        const { PhotosLayer } = await operation.wait(
          import("../layers/photos.js"),
        )
        operation.check()
        photos = new PhotosLayer(map, {
          reader,
          library,
          timezone: loadedConfig.range.timezone,
          labels: config.photoLabels,
          onError: (code) => pushEvent("map:failed", { code }),
        })
        photos.add()
        if (
          (await operation.wait(
            photos.load(loadedConfig.range, { signal }),
          )) !== "ready"
        )
          throw new Error("Photos unavailable")
        if (owner.replay?.active) photos.hide()
      }
    },
    events: {
      refreshed: (receipt) => pushEvent("map:ready", receipt),
      error: (receipt) => pushEvent("map:failed", receipt),
    },
  })
  owner.source = createStudioSource({
    fixedRange: true,
    getState: () => ({
      ...(loadedConfig ?? owner.config),
      revision: owner.config.revision,
    }),
    readSnapshot: async (state, { purpose, signal }) => {
      const { data } = await reader.read(
        "trip",
        { id: state.tripId },
        { signal },
      )
      if (JSON.stringify(data.config.range) !== JSON.stringify(state.range))
        throw cancelled()
      const snapshot = await readRouteSnapshot(
        reader,
        { ...state, range: data.config.range },
        {
          purpose,
          signal,
          deviceWindows: data.deviceWindows,
          routeOptions: data.config.routeOptions,
        },
      )
      return snapshot
    },
  })
  Object.defineProperty(owner, "layers", { get: () => layers })
  const destroy = owner.destroy
  owner.destroy = () => {
    owner.source.destroy()
    destroy()
  }
  return owner
}
