import { mapTranslate } from "./translate.js"

export function createPointSelection({ map, lifetime, getConfig, info }) {
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
      const zoom = map.getZoom()
      const next = Math.min(zoom + 2, map.getMaxZoom?.() ?? 22)
      if (next > zoom)
        map.easeTo?.({ center: event.lngLat, zoom: next, duration: 350 })
      else
        info.show(
          translate("map_info.location_point"),
          `<p>${translate("map_info.overlapping_points", { count: count || 2 })}</p>`,
        )
      return
    }
    if (point.id == null) return
    info.point(point, feature.geometry)
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
