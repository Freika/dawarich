export function rectangleGesture(map, onBounds, onDraw = () => {}) {
  let origin = null

  const corner = (point) => map.unproject([point.x, point.y])

  const onDown = (event) => {
    event.preventDefault?.()
    origin = event.point
  }

  const bounds = (a, b) => ({
    minLng: Math.min(a.lng, b.lng),
    maxLng: Math.max(a.lng, b.lng),
    minLat: Math.min(a.lat, b.lat),
    maxLat: Math.max(a.lat, b.lat),
  })
  const onMove = (event) => {
    if (origin) onDraw(bounds(corner(origin), corner(event.point)))
  }

  const onUp = (event) => {
    if (!origin) return
    const a = corner(origin)
    const b = corner(event.point)
    origin = null
    const selected = bounds(a, b)
    onDraw(selected)
    onBounds(selected)
  }

  map.on("mousedown", onDown)
  map.on("mousemove", onMove)
  map.on("mouseup", onUp)
  map.getCanvas().style.cursor = "crosshair"

  return {
    release() {
      map.off("mousedown", onDown)
      map.off("mousemove", onMove)
      map.off("mouseup", onUp)
      map.getCanvas().style.cursor = ""
    },
  }
}
