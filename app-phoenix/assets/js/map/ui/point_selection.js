import { mapTranslate } from "./translate.js"

export function createPointSelection({
  map,
  root,
  pushEvent,
  lifetime,
  getConfig,
}) {
  const summary = root?.querySelector("[data-map-point-summary]")
  const translate = mapTranslate(getConfig)
  function select(event) {
    const feature = event.features?.[0]
    const point = feature?.properties
    if (!point) return
    const count = Math.max(
      Number(point.count ?? 1),
      Number(point.point_count ?? 1),
    )
    if (point.cluster || count > 1) {
      pushEvent("address:close", {})
      const zoom = map.getZoom()
      const next = Math.min(zoom + 2, map.getMaxZoom?.() ?? 22)
      if (summary) summary.textContent = ""
      if (next > zoom)
        map.easeTo?.({ center: event.lngLat, zoom: next, duration: 350 })
      else if (summary)
        summary.textContent = translate("map_info.overlapping_points", {
          count: count || 2,
        })
      return
    }
    const coordinates = feature.geometry?.coordinates
    if (
      summary &&
      coordinates?.length === 2 &&
      coordinates.every(Number.isFinite)
    )
      summary.textContent = translate("map_info.location_coordinates", {
        latitude: coordinates[1].toFixed(6),
        longitude: coordinates[0].toFixed(6),
      })
    pushEvent("address:open", { id: point.id })
  }
  const hover = (event) => {
    const point = event.features?.[0]?.properties
    if (!point) return
    map.getCanvas().style.cursor =
      Number(point.count ?? point.point_count ?? 1) > 1 &&
      map.getZoom() < (map.getMaxZoom?.() ?? 22)
        ? "zoom-in"
        : "pointer"
  }
  const leave = () => {
    map.getCanvas().style.cursor = ""
  }
  map.on("mousemove", "points-mvt", hover)
  map.on("mouseleave", "points-mvt", leave)
  lifetime.own(() => {
    map.off("mousemove", "points-mvt", hover)
    map.off("mouseleave", "points-mvt", leave)
  })
  map.on("click", "points-mvt", select)
  lifetime.own(() => map.off("click", "points-mvt", select))
}
