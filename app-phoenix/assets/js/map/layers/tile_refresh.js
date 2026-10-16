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

export function retryTileSource(map, sourceId) {
  const source = map.getSource(sourceId)
  const tiles = source?.serialize?.().tiles
  if (source?.setTiles && Array.isArray(tiles)) source.setTiles(tiles)
  else if (source) map.refreshTiles?.(sourceId)
}
