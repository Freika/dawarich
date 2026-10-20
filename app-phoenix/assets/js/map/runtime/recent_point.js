import { mapNotify } from "../ui/notify.js"
import { createRequestScope } from "../data/request_scope.js"
import { RecentPointLayer } from "../layers/recent_point.js"
export function createHostRecentPoint({ map, reader, lifetime, config }) {
  const requests = createRequestScope()
  const layer = new RecentPointLayer(map, { visible: false })
  let state = config,
    destroyed = false,
    primed = false,
    pending = false,
    latest = null
  const key = (value) => JSON.stringify([value.range, value.liveEnabled])
  const clear = () => {
    requests.reset()
    primed = false
    pending = false
    latest = null
    layer.clear()
    layer.hide()
  }
  const params = (current) => ({
    start_at: current.range.startAt,
    end_at: current.range.endAt,
    import_id: current.range.importId,
    order: "desc",
    per_page: 1,
  })
  const identity = (row) =>
    row
      ? JSON.stringify([
          row.id,
          row.timestamp,
          row.revision,
          row.latitude,
          row.longitude,
        ])
      : null
  async function baseline({ signal } = {}) {
    if (destroyed || state.liveEnabled !== true) return
    if (pending) return deliver({ kinds: ["points"] }, { signal })
    if (primed) return
    const operation = requests.begin(signal)
    try {
      const result = await operation.wait(
        reader.read("points", params(state), { signal: operation.signal }),
      )
      operation.check()
      latest = identity(result.data?.[0])
      primed = true
    } catch {
    } finally {
      operation.close()
    }
  }
  async function deliver(receipt = {}, { signal } = {}) {
    if (
      destroyed ||
      state.liveEnabled !== true ||
      !receipt.kinds?.includes("points")
    )
      return
    const operation = requests.begin(signal),
      current = state
    try {
      const result = await operation.wait(
        reader.read("points", params(current), { signal: operation.signal }),
      )
      operation.check()
      const row = result.data?.[0],
        lat = Number(row?.latitude),
        lon = Number(row?.longitude)
      if (
        !row ||
        !Number.isFinite(lat) ||
        !Number.isFinite(lon) ||
        Math.abs(lat) > 90 ||
        Math.abs(lon) > 180
      )
        return
      pending = false
      if (identity(row) === latest) return
      latest = identity(row)
      layer.add()
      layer.updateRecentPoint(lon, lat, {
        id: row.id,
        timestamp: row.timestamp,
      })
      layer.show()
      mapNotify(() => state)("info", "messages.new_location_recorded")
      map.flyTo({
        center: [lon, lat],
        zoom: Math.max(map.getZoom(), 14),
        duration: 2000,
        essential: true,
      })
    } catch {
    } finally {
      operation.close()
    }
  }
  lifetime.own(() => {
    destroyed = true
    requests.destroy()
    layer.remove()
  })
  return {
    baseline,
    prepare(receipt) {
      if (state.liveEnabled === true && receipt?.kinds?.includes("points")) {
        requests.reset()
        primed = true
        pending = true
      }
    },
    deliver,
    config(next) {
      if (key(next) !== key(state)) clear()
      state = next
    },
  }
}

export function installRecentReconnect(
  owner,
  getLayers,
  getRecent,
  invalidateEditing = () => {},
) {
  const reconnect = owner.reconnect
  owner.reconnect = async (receipt) => {
    if (
      !receipt ||
      receipt.kinds?.some(
        (kind) => kind === "map_edits" || kind === "reconnect",
      )
    )
      await invalidateEditing(receipt)
    getRecent()?.prepare(receipt)
    const state = await reconnect.call(owner)
    if (state === "ready") {
      getLayers()?.points.refresh()
      getLayers()?.tracks.refresh()
      await getRecent()?.deliver(receipt)
    }
    return state
  }
}
