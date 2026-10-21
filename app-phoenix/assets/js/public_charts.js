import { createAdapter } from "./charts/adapter.js"

const mounted = new WeakMap()
const previews = new WeakMap()

export function initializeCharts(root = document, factory = createAdapter) {
  const adapters = Array.from(root.querySelectorAll("[data-chart]")).map(
    (element) => {
      if (mounted.has(element)) return mounted.get(element)
      const adapter = factory(element.matches?.("[data-chart-plot]") ? element : element.querySelector("[data-chart-plot]"))
      let alive = true
      const entry = {
        destroy() {
          if (!alive) return
          alive = false
          adapter.destroy()
          mounted.delete(element)
        },
      }
      mounted.set(element, entry)
      adapter.update(JSON.parse(element.dataset.chart)).catch(() => {
        element.dataset.chartStatus = "error"
      })
      return entry
    },
  )
  return () =>
    adapters.forEach((adapter) => {
      adapter.destroy()
    })
}

export function initializePublicCharts(
  root = document,
  target = window,
  factory = createAdapter,
) {
  const cleanup = initializeCharts(root, factory)
  const hide = (event) => {
    if (!event.persisted) cleanup()
  }
  target.addEventListener("pagehide", hide)
  return () => {
    target.removeEventListener("pagehide", hide)
    cleanup()
  }
}

export function trackPreviewLoading(element, createObserver = (changed) => new MutationObserver(changed)) {
  const loading = element.closest?.("[data-native-public-map-frame]")?.querySelector("[data-native-map-loading]")
  if (loading == null) return () => {}
  let alive = true
  const changed = () => {
    if (alive) loading.hidden = ["ready", "failed"].includes(element.dataset.mapState)
  }
  const observer = createObserver(changed)
  observer.observe(element, { attributes: true, attributeFilter: ["data-map-state"] })
  changed()
  return () => {
    if (!alive) return
    alive = false
    observer.disconnect()
  }
}

export function initializePublicPreviews(
  root = document,
  target = window,
  load = () => import("./map/preview/runtime.js"),
) {
  let alive = true
  const owners = []
  const elements = Array.from(root.querySelectorAll("[phx-hook=MapPreview]"))
  const loadingStops = elements.map((element) => trackPreviewLoading(element))
  const cleanup = () => {
    alive = false
    for (const stop of loadingStops) stop()
    for (const owner of owners) owner.destroy()
    owners.length = 0
  }
  const hide = (event) => {
    if (!event.persisted) cleanup()
  }
  target.addEventListener("pagehide", hide)
  if (elements.length)
    load()
      .then(({ mountPreview }) => {
        if (!alive) return
        for (const element of elements) {
          let entry = previews.get(element)
          if (!entry) {
            const owner = mountPreview({ element })
            let disposed = false
            entry = {
              destroy() {
                if (disposed) return
                disposed = true
                owner.destroy()
                previews.delete(element)
              },
            }
            previews.set(element, entry)
            owner.mount()
          }
          owners.push(entry)
        }
      })
      .catch(() => {
        if (alive)
          for (const element of elements) element.dataset.mapState = "failed"
      })
  return () => {
    target.removeEventListener("pagehide", hide)
    cleanup()
  }
}

if (typeof document !== "undefined") {
  initializePublicCharts()
  initializePublicPreviews()
}
