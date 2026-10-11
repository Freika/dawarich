export function queueTileRefresh(map, sourceId) {
  let pending = true
  const cancel = () => {
    if (!pending) return
    pending = false
    map.off("render", render)
  }
  const render = () => {
    cancel()
    if (map.getSource(sourceId)) map.refreshTiles(sourceId)
  }
  map.on("render", render)
  map.triggerRepaint?.()
  return cancel
}
