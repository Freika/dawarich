const KINDS = new Set(["place", "visit"])
const round = (value) => Math.round(value * 1e6) / 1e6

export function createEntityEditor({ map, pushEvent }) {
  let destroyed = false
  let click = null

  function disarm() {
    if (click) map.off("click", click)
    click = null
    map.getCanvas().style.cursor = ""
  }

  function arm(kind) {
    disarm()
    if (destroyed || !KINDS.has(kind)) return
    click = (event) => {
      disarm()
      pushEvent(`${kind}:new`, {
        latitude: round(event.lngLat.lat),
        longitude: round(event.lngLat.lng),
      })
    }
    map.on("click", click)
    map.getCanvas().style.cursor = "crosshair"
  }

  function destroy() {
    if (destroyed) return
    destroyed = true
    disarm()
  }

  return { arm, disarm, destroy }
}
