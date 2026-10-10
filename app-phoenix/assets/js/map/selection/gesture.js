export function rectangleGesture(map, onBounds) {
  let origin = null

  const corner = (point) => map.unproject([point.x, point.y])

  const onDown = (event) => {
    event.preventDefault?.()
    origin = event.point
  }

  const onMove = () => {}

  const onUp = (event) => {
    if (!origin) return
    const a = corner(origin)
    const b = corner(event.point)
    origin = null
    onBounds({
      minLng: Math.min(a.lng, b.lng),
      maxLng: Math.max(a.lng, b.lng),
      minLat: Math.min(a.lat, b.lat),
      maxLat: Math.max(a.lat, b.lat),
    })
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
