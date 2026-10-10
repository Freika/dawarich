import { rectangleGesture } from "./gesture.js"

export function createAreaSelection({
  map,
  query,
  getRange,
  pushEvent,
  onChange = () => {},
}) {
  const state = { points: [], visits: [], bounds: null }
  let controller = null
  let gesture = null
  let generation = 0
  let ready = Promise.resolve()

  function restore() {
    gesture?.release()
    gesture = null
    map.dragPan.enable()
    map.boxZoom.enable()
  }

  function start() {
    cancel()
    map.dragPan.disable()
    map.boxZoom.disable()
    gesture = rectangleGesture(map, (bounds) => {
      restore()
      load(bounds)
    })
  }

  function load(bounds) {
    const current = ++generation
    controller = new AbortController()
    state.bounds = bounds
    ready = query
      .select(bounds, getRange(), { signal: controller.signal })
      .then((result) => {
        if (current !== generation) return
        state.points = result.points
        state.visits = result.visits
        onChange()
      })
      .catch(() => {})
    return ready
  }

  function cancel() {
    generation++
    controller?.abort()
    controller = null
    restore()
    state.points = []
    state.visits = []
    state.bounds = null
    onChange()
  }

  function refresh() {
    return state.bounds ? load(state.bounds) : Promise.resolve()
  }

  function bulkVisits(action, ids) {
    return new Promise((resolve) => {
      pushEvent("visits:bulk", { action, ids: ids.map(String) }, (reply) => {
        if (!reply?.ok) return resolve({ status: "error", error: reply?.error })
        refresh().then(() => resolve({ status: "done" }))
      })
    })
  }

  function deletePoints(ids = state.points.map((point) => point.id)) {
    return new Promise((resolve) => {
      pushEvent("points:bulk_delete", { point_ids: ids }, (reply) => {
        if (!reply?.ok) return resolve({ status: "error", error: reply?.error })
        const removed = new Set(ids)
        state.points = state.points.filter((point) => !removed.has(point.id))
        onChange()
        resolve({ status: "deleted", count: reply.count })
      })
    })
  }

  return {
    start,
    cancel,
    deletePoints,
    bulkVisits,
    refresh,
    state,
    get ready() {
      return ready
    },
  }
}
