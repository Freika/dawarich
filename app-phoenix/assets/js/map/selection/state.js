import { rectangleGesture } from "./gesture.js"

export function createAreaSelection({
  map,
  query,
  getRange,
  pushEvent,
  onChange = () => {},
  onDraw = () => {},
  notify = () => {},
  translate = key => key,
}) {
  const state = { active: false, points: [], visits: [], bounds: null }
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
    cancel(false)
    notify("info", "messages.draw_a_rectangle_on_the_map_to_select_points")
    state.active = true
    onChange()
    map.dragPan.disable()
    map.boxZoom.disable()
    gesture = rectangleGesture(
      map,
      (bounds) => {
        restore()
        load(bounds)
      },
      onDraw,
    )
  }

  function load(bounds, feedback = true) {
    if (feedback) notify("info", "messages.fetching_data_in_selected_area")
    const current = ++generation
    controller = new AbortController()
    state.bounds = bounds
    ready = query
      .select(bounds, getRange(), { signal: controller.signal })
      .then(async (result) => {
        if (current !== generation) return
        if (feedback && !result.points.length && !result.visits.length) {
          notify("info", "messages.no_data_found_in_selected_area")
          cancel()
          return
        }
        const items = [
          result.points.length && translate("selection.points", { count: result.points.length }),
          result.visits.length && translate("selection.visits", { count: result.visits.length }),
        ].filter(Boolean).join(` ${translate("common.and")} `)
        if (feedback) notify("success", "selection.selected", { items })
        state.points = result.points
        state.visits = result.visits
        await onChange()
      })
      .catch(() => {
        if (current !== generation) return
        if (!feedback) throw new Error("selection_refresh_failed")
        notify("error", "messages.failed_to_fetch_data_in_selected_area")
        cancel()
      })
    return ready
  }

  function cancel(feedback = true) {
    if (feedback && state.active) notify("info", "messages.selection_cancelled")
    generation++
    controller?.abort()
    controller = null
    restore()
    state.active = false
    state.points = []
    state.visits = []
    state.bounds = null
    onChange()
  }

  function refresh() {
    return state.bounds ? load(state.bounds, false) : Promise.resolve()
  }

  function bulkVisits(action, ids) {
    return new Promise((resolve) => {
      pushEvent("visits:bulk", { action, ids: ids.map(String) }, (reply) => {
        if (!reply?.ok) return resolve({ status: "error", error: reply?.error })
        refresh().then(() => resolve({ status: "done" })).catch(() => resolve({ status: "error" }))
      })
    })
  }

  function deletePoints(ids = state.points.map((point) => point.id)) {
    return new Promise((resolve) => {
      state.deletingPoints = true
      pushEvent("points:bulk_delete", { point_ids: ids }, (reply) => {
        if (!reply?.ok) { state.deletingPoints = false; return resolve({ status: "error", ...reply }) }
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
