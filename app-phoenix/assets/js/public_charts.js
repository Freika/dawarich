import { createAdapter } from "./charts/adapter.js"

const mounted = new WeakMap()

export function initializeCharts(root = document, factory = createAdapter) {
  const adapters = Array.from(root.querySelectorAll("[data-chart]")).map(
    (element) => {
      if (mounted.has(element)) return mounted.get(element)
      const adapter = factory(element.querySelector("[data-chart-plot]"))
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

if (typeof document !== "undefined") {
  initializePublicCharts()
}
