const prefix = "dawarich:native:map:lastView:"
const validNamespace = (value) =>
  typeof value === "string" && /^user:[1-9]\d{0,17}$/.test(value)
function valid(view) {
  return (
    Array.isArray(view?.center) &&
    view.center.length === 2 &&
    view.center.every(Number.isFinite) &&
    Math.abs(view.center[0]) <= 180 &&
    Math.abs(view.center[1]) <= 90 &&
    Number.isFinite(view.zoom)
  )
}
export function createViewStore({ namespace, storage } = {}) {
  let current = validNamespace(namespace) ? namespace : null
  return {
    get namespace() {
      return current
    },
    updateNamespace(next) {
      current = validNamespace(next) ? next : null
    },
    load() {
      if (!current) return null
      try {
        const view = JSON.parse(
          (storage ?? globalThis.localStorage).getItem(prefix + current) ??
            "null",
        )
        return valid(view)
          ? { center: [...view.center], zoom: view.zoom }
          : null
      } catch {
        return null
      }
    },
    save(map) {
      if (!current) return false
      try {
        const center = map.getCenter(),
          view = { center: [center.lng, center.lat], zoom: map.getZoom() }
        if (!valid(view)) return false
        ;(storage ?? globalThis.localStorage).setItem(
          prefix + current,
          JSON.stringify(view),
        )
        return true
      } catch {
        return false
      }
    },
  }
}
export function attachViewportStore({
  map,
  namespace,
  storage,
  fallback = { center: [0, 0], zoom: 1 },
}) {
  const store = createViewStore({ namespace, storage })
  let destroyed = false,
    restoring = false
  const save = () => {
    if (!destroyed && !restoring) store.save(map)
  }
  function restore() {
    if (destroyed) return
    restoring = true
    try {
      map.jumpTo(store.load() ?? fallback)
    } finally {
      restoring = false
    }
  }
  map.on("moveend", save)
  return {
    restore,
    updateNamespace(next) {
      if (destroyed || next === store.namespace) return
      store.updateNamespace(next)
      restore()
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      map.off("moveend", save)
    },
  }
}
