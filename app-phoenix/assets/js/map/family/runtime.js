import { createReader } from "../data/reader.js"
import { createRequestScope } from "../data/request_scope.js"
import { createMapRuntime } from "../runtime/create_map.js"
import { createFamilyOverlay } from "./overlay.js"
export function mountFamily({
  element,
  pushEvent,
  reader = createReader(),
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  loadStyle = async (config, { signal }) => {
    const response = await fetch(
      config.styleUrl ?? "/maps_maplibre/styles/light.json",
      { signal, credentials: "same-origin" },
    )
    if (!response.ok) throw new Error("Style unavailable")
    return response.json()
  },
  timers = globalThis,
}) {
  let overlay, library, overlayLocale
  const reads = createRequestScope(timers)
  const owner = createMapRuntime({
    element,
    config: JSON.parse(element.dataset.mapConfig ?? "{}"),
    reader,
    timers,
    loadLibrary: async (options) => {
      library = await loadLibrary(options)
      return library
    },
    loadStyle,
    attach: ({ map, config, lifetime }) =>
      new Promise((resolve) => {
        const ready = () => {
          overlayLocale = JSON.stringify([config.locale, config.familyTime])
          overlay = createFamilyOverlay({
            map,
            library,
            locale: config.locale,
            labels: config.familyTime,
            timers,
            colorMode: config.colorMode,
          })
          lifetime.own(() => overlay.destroy())
          resolve(() => map.off("load", ready))
        }
        if (map.loaded()) ready()
        else {
          map.once("load", ready)
          lifetime.own(() => map.off("load", ready))
        }
      }),
    refresh: async ({ map, config, operation, signal }) => {
      const desired = JSON.stringify([config.locale, config.familyTime])
      if (desired !== overlayLocale) {
        overlay.destroy()
        overlay = createFamilyOverlay({
          map,
          library,
          locale: config.locale,
          labels: config.familyTime,
          timers,
          colorMode: config.colorMode,
        })
        overlayLocale = desired
      }
      overlay.clear()
      reads.reset()
      const read = reads.begin(signal)
      try {
        const [latest, history] = await operation.wait(
          read.wait(
            Promise.all([
              reader.read("family_locations", {}, { signal }),
              config.range?.startAt && config.range?.endAt
                ? reader.read(
                    "family_history",
                    {
                      start_at: config.range.startAt,
                      end_at: config.range.endAt,
                    },
                    { signal },
                  )
                : Promise.resolve({ data: { members: [] } }),
            ]),
          ),
        )
        operation.check()
        read.check()
        overlay.replace(latest.data.locations, history.data.members)
      } finally {
        read.close()
      }
    },
    events: {
      refreshed: (receipt) => pushEvent("map:ready", receipt),
      error: (receipt) => pushEvent("map:failed", receipt),
    },
  })
  owner.clear = () => {
    reads.reset()
    reader.reset()
    overlay?.clear()
  }
  const destroy = owner.destroy
  owner.destroy = () => {
    reads.destroy()
    overlay?.clear()
    destroy()
  }
  return owner
}
