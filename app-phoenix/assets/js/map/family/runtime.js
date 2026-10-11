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
  now = Date.now,
}) {
  const empty = element.querySelector?.("[data-family-empty]")
  let overlay, library, overlayLocale, leaseTimer, leaseToken
  let destroyed = false
  let leaseDeadline = now() + 30000
  const reads = createRequestScope(timers)
  const initial = JSON.parse(element.dataset.mapConfig ?? "{}")
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
      if (empty) empty.hidden = false
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
        if (now() >= leaseDeadline) return
        overlay.replace(latest.data.locations, history.data.members)
        if (empty) empty.hidden = latest.data.locations.length > 0
      } finally {
        read.close()
      }
    },
    events: {
      refreshed: (receipt) => pushEvent("map:ready", receipt),
      error: (receipt) => pushEvent("map:failed", receipt),
    },
  })
  owner.lease = ({ milliseconds = 30000 } = {}) => {
    if (destroyed) return
    timers.clearTimeout(leaseTimer)
    const delay = Math.max(0, Math.min(30000, Number(milliseconds) || 0))
    leaseDeadline = Math.min(leaseDeadline, now() + delay)
    const token = {}
    leaseToken = token
    leaseTimer = timers.setTimeout(
      () => {
        if (destroyed || token !== leaseToken) return
        owner.clear()
        owner.lease({ milliseconds: 30000 })
        void owner.reconnect()
      },
      Math.max(0, leaseDeadline - now()),
    )
  }
  owner.lease({ milliseconds: initial.consentLeaseMs ?? 30000 })
  owner.clear = () => {
    leaseToken = null
    leaseDeadline = now() + 30000
    reads.reset()
    reader.reset()
    overlay?.clear()
    if (empty) empty.hidden = false
  }
  const destroy = owner.destroy
  owner.destroy = () => {
    destroyed = true
    timers.clearTimeout(leaseTimer)
    reads.destroy()
    overlay?.clear()
    destroy()
  }
  return owner
}
