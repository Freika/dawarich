import { bindPublicDays, syncPublicDays } from "./day_hover.js"
import { cancelled } from "../data/request_scope.js"
import { createStudioSource } from "../data/studio_source.js"
import { installHostReplay } from "../replay/host.js"
import { createMapRuntime } from "../runtime/create_map.js"
import { waitForStyle } from "../runtime/style_ready.js"
import { createPublicLayers } from "./layers.js"
import { createPublicReader } from "./reader.js"
function sameGrant(before, after) {
  const { validUntil: previous, ...grant } = before
  const { validUntil: current, ...fresh } = after
  const oldDeadline = Date.parse(previous),
    newDeadline = Date.parse(current)
  return (
    JSON.stringify(grant) === JSON.stringify(fresh) &&
    (previous === current ||
      (typeof previous === "string" &&
        typeof current === "string" &&
        Number.isFinite(oldDeadline) &&
        Number.isFinite(newDeadline) &&
        newDeadline >= oldDeadline))
  )
}
export function mountPublic({
  element,
  pushEvent,
  reader,
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  loadStyle = async (config, { signal }) => {
    const response = await fetch(
      `/maps_maplibre/styles/${config.styleName === "dark" ? "dark" : "light"}.json`,
      { signal, credentials: "same-origin" },
    )
    if (!response.ok) throw new Error("Style unavailable")
    return response.json()
  },
  createLayers = createPublicLayers,
  timers = globalThis,
  loadPhotos = async (options) => {
    const { PhotosLayer } = await import("../layers/photos.js")
    if (options.signal.aborted) throw cancelled()
    return new PhotosLayer(options.map, options)
  },
}) {
  const initial = JSON.parse(element.dataset.mapConfig ?? "{}")
  reader ??= createPublicReader({ shareId: initial.shareId })
  let selectedDay = null,
    root
  const syncDays = () =>
    syncPublicDays(
      root,
      (day) => current && layers?.getDayColor?.(day),
      current ? selectedDay : null,
    )
  let library, layers, photos, current
  function clear() {
    current = null
    layers?.clear()
    photos?.remove()
    photos = null
    syncDays()
  }
  async function readGrant({ signal, purpose }) {
    const { data: metadata } = await reader.read("metadata", {}, { signal })
    if (metadata.shareId !== initial.shareId)
      throw new Error("Public capability changed")
    const { data: points } = await reader.read("points", {}, { signal })
    const route =
      metadata.publicType === "live" && metadata.routeEnabled
        ? (await reader.read("route", {}, { signal })).data
        : []
    const images =
      purpose === "replay" && metadata.photosEnabled
        ? await reader.pages("photos", {}, { signal })
        : []
    const { data: fresh } = await reader.read("metadata", {}, { signal })
    if (!sameGrant(metadata, fresh)) throw new Error("Public grant changed")
    return { metadata, points, route, photos: images }
  }
  const owner = createMapRuntime({
    element,
    config: initial,
    reader,
    timers,
    loadLibrary: async (options) => {
      library = await loadLibrary(options)
      return library
    },
    loadStyle,
    attach: ({ map, lifetime, operation }) => {
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
        onDay: (day) => pushEvent("public:day", { day }),
      })
      root = element.closest?.("[data-native-map-root]")
      lifetime.own(
        bindPublicDays(root, {
          preview: (day) => layers?.previewDay(day),
          selected: () => selectedDay,
          allowed: () => current != null,
          hasDay: (day) => !!layers?.getDayColor?.(day),
          sync: syncDays,
        }),
      )
      lifetime.own(() => {
        clear()
        layers.destroy()
      })
      return operation.wait(waitForStyle(map, lifetime))
    },
    refresh: async ({ map, config, operation, signal }) => {
      const data = await operation.wait(readGrant({ signal }))
      operation.check()
      clear()
      current = { ...config, ...data.metadata, revision: config.revision }
      layers.show(data, current)
      syncDays()
      if (current.photosEnabled) {
        const pending = Promise.resolve(
          loadPhotos({
            map,
            library,
            reader,
            timezone: current.range.timezone,
            labels: config.photoLabels,
            onError: (code) => pushEvent("map:failed", { code }),
            signal,
          }),
        )
        pending.then(
          (layer) => {
            if (signal.aborted) layer.remove()
          },
          () => {},
        )
        photos = await operation.wait(pending)
        operation.check()
        photos.add()
        if (
          (await operation.wait(photos.load(current.range, { signal }))) !==
          "ready"
        )
          throw new Error("Public photos unavailable")
        if (owner.replay?.active) photos.hide()
      }
    },
    events: {
      refreshed: (receipt) => pushEvent("map:ready", receipt),
      error: (receipt) => {
        clear()
        pushEvent("map:failed", receipt)
      },
    },
  })
  owner.source = createStudioSource({
    fixedRange: true,
    getState: () => ({
      ...(current ?? owner.config),
      revision: owner.config.revision,
    }),
    readSnapshot: async (state, { purpose, signal }) => {
      if (purpose !== "replay") throw new Error("Public studio unavailable")
      const data = await readGrant({ signal, purpose })
      for (const key of [
        "shareId",
        "publicType",
        "range",
        "photosEnabled",
        "routeEnabled",
      ])
        if (JSON.stringify(data.metadata[key]) !== JSON.stringify(state[key]))
          throw cancelled()
      return {
        points: data.points.map(([longitude, latitude, timestamp]) => ({
          longitude,
          latitude,
          timestamp,
        })),
        photos: data.photos,
      }
    },
  })
  const update = owner.update
  owner.update = (next) => update.call(owner, { ...owner.config, ...next })
  owner.selectDay = (day) => {
    if (layers?.selectDay(day) === false) return
    selectedDay = day
    syncDays()
  }
  const destroy = owner.destroy
  owner.destroy = () => {
    owner.source.destroy()
    destroy()
  }
  return owner
}
