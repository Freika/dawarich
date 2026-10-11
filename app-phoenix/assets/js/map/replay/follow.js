const INTERRUPTS = ["mousedown", "touchstart", "wheel", "dragstart"]
const EASE = 0.08

export function createFollowCamera({ map, onChange = () => {} }) {
  let following = false
  let bound = false
  let destroyed = false

  const interrupt = () => {
    if (!following) return
    following = false
    onChange(false)
  }

  function start() {
    if (destroyed) return
    if (!bound) for (const event of INTERRUPTS) map.on(event, interrupt)
    bound = true
    following = true
    onChange(true)
  }

  function panTo(lon, lat) {
    if (destroyed || !following) return
    const center = map.getCenter()
    const bounds = map.getBounds()
    const lngSpan = bounds.getEast() - bounds.getWest()
    const latSpan = bounds.getNorth() - bounds.getSouth()
    if (lngSpan <= 0 || latSpan <= 0) return
    const far =
      Math.abs((lon - center.lng) / lngSpan) > 0.75 ||
      Math.abs((lat - center.lat) / latSpan) > 0.75
    if (far) return map.setCenter([lon, lat])
    map.setCenter([
      center.lng + (lon - center.lng) * EASE,
      center.lat + (lat - center.lat) * EASE,
    ])
  }

  function recenter(lngLat) {
    if (destroyed) return
    following = true
    onChange(true)
    if (lngLat) map.easeTo({ center: lngLat, duration: 400 })
  }

  function destroy() {
    destroyed = true
    following = false
    if (bound) for (const event of INTERRUPTS) map.off(event, interrupt)
    bound = false
  }

  return {
    start,
    panTo,
    recenter,
    destroy,
    get following() {
      return following
    },
  }
}
