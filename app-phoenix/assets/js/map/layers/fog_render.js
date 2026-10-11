export function drawPointHoles(layer) {
  const minRadius = layer.tiledSource ? (layer.map.getZoom() < 14 ? 4 : 1) : 0

  layer.points.forEach((feature) => {
    const coords = feature.geometry.coordinates
    const point = layer.map.project(coords)
    const metersPerPixel = layer.getMetersPerPixel(coords[1])
    const radiusPixels = Math.max(layer.clearRadius / metersPerPixel, minRadius)

    layer.ctx.beginPath()
    layer.ctx.arc(point.x, point.y, radiusPixels, 0, Math.PI * 2)
    layer.ctx.fill()
  })
}

export function drawHexagonHoles(layer) {
  const bounds = layer.map.getBounds()
  const west = bounds.getWest()
  const east = bounds.getEast()
  const south = bounds.getSouth()
  const north = bounds.getNorth()

  layer.ctx.strokeStyle = "rgba(0, 0, 0, 1)"
  layer.ctx.lineWidth = 1.5

  for (const hex of layer.hexBoundaries) {
    if (
      hex.maxLng < west ||
      hex.minLng > east ||
      hex.maxLat < south ||
      hex.minLat > north
    ) {
      continue
    }

    layer.ctx.beginPath()
    hex.coords.forEach(([lng, lat], i) => {
      const point = layer.map.project([lng, lat])
      if (i === 0) {
        layer.ctx.moveTo(point.x, point.y)
      } else {
        layer.ctx.lineTo(point.x, point.y)
      }
    })
    layer.ctx.closePath()
    layer.ctx.fill()
    layer.ctx.stroke()
  }
}

export function attachTiledHandlers(layer) {
  if (layer._tiledRefreshHandler) return

  layer._tiledRefreshHandler = () => layer._scheduleTiledRefresh()
  layer._sourceDataHandler = (event) => {
    if (event?.sourceId !== layer.tiledSourceId) return
    layer._scheduleTiledRefresh()
  }
  layer.map.on("moveend", layer._tiledRefreshHandler)
  layer.map.on("zoomend", layer._tiledRefreshHandler)
  layer.map.on("sourcedata", layer._sourceDataHandler)
}

export function detachTiledHandlers(layer) {
  if (layer._tiledRefreshHandler) {
    layer.map.off("moveend", layer._tiledRefreshHandler)
    layer.map.off("zoomend", layer._tiledRefreshHandler)
    layer._tiledRefreshHandler = null
  }
  if (layer._sourceDataHandler) {
    layer.map.off("sourcedata", layer._sourceDataHandler)
    layer._sourceDataHandler = null
  }
  if (layer._tiledRefreshTimer) {
    layer.timers.clearTimeout(layer._tiledRefreshTimer)
    layer._tiledRefreshTimer = null
  }
}

export function resizeCanvas(layer) {
  if (!layer.canvas) return

  const container = layer.map.getContainer()
  layer.canvas.width = container.offsetWidth
  layer.canvas.height = container.offsetHeight
  layer.render()
}

export function metersPerPixel(layer, latitude) {
  const earthCircumference = 40075017
  const latitudeRadians = (latitude * Math.PI) / 180
  const zoom = layer.map.getZoom()
  return (earthCircumference * Math.cos(latitudeRadians)) / (256 * 2 ** zoom)
}
