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

export function retryTileSource(layer, kind) {
  const map = layer.map
  if (!map.getSource(layer.sourceId)) return
  const filters = layer.getLayerIds().map(id => [id,map.getFilter?.(id)])
  const before = layer._layerAbove()
  layer.freshness?.bump(kind)
  layer.remove()
  layer.add(undefined, before)
  for (const [id, filter] of filters)
    if (filter != null && map.getLayer(id)) map.setFilter(id,filter)
}
