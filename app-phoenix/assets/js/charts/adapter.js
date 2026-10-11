const kinds = new Set([
  "ColumnChart",
  "BarChart",
  "LineChart",
  "AreaChart",
  "PieChart",
])
const loadLibrary = () =>
  import("./library.js").then((module) => module.default)

export function createAdapter(element, load = loadLibrary) {
  let alive = true
  let version = 0
  let generation = -1
  let revision
  let chart
  let kind
  let loading
  return {
    async update(payload) {
      if (!alive || payload.generation < generation) return
      if (
        !kinds.has(payload.kind) ||
        !Array.isArray(payload.data) ||
        payload.data.length > 366
      )
        throw new Error("invalid chart")
      if (payload.generation === generation && payload.revision === revision)
        return
      generation = payload.generation
      revision = payload.revision
      const current = ++version
      let library
      try {
        loading ||= load()
        library = await loading
      } catch (error) {
        loading = null
        if (current === version) revision = undefined
        throw error
      }
      if (!alive || current !== version) return
      if (chart && kind !== payload.kind) {
        chart.destroy()
        chart = null
      }
      kind = payload.kind
      if (chart) chart.updateData(payload.data, payload.options)
      else chart = new library[kind](element, payload.data, payload.options)
    },
    destroy() {
      if (!alive) return
      alive = false
      version++
      chart?.destroy()
      chart = null
    },
  }
}
