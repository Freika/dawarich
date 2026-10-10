export function createStatsLayer({
  map,
  library,
  labels = {},
  locale = "en",
  timezone = "UTC",
}) {
  let popup,
    hovered = null,
    disposed = false
  const t = (key) => labels[key] ?? key
  function close() {
    popup?.remove()
    popup = null
  }
  function clearHover() {
    map.getCanvas().style.cursor = ""
    if (hovered !== null && map.getSource("hexagons"))
      map.setFeatureState({ source: "hexagons", id: hovered }, { hover: false })
    hovered = null
  }
  function hover(event) {
    const feature = event.features?.[0]
    if (!feature) return
    clearHover()
    hovered = feature.id
    map.getCanvas().style.cursor = "pointer"
    map.setFeatureState({ source: "hexagons", id: hovered }, { hover: true })
  }
  function click(event) {
    const feature = event.features?.[0]
    if (!feature || disposed) return
    close()
    const p = feature.properties
    const format = (value) =>
      value
        ? new Date(value).toLocaleString(locale, { timeZone: timezone })
        : t("common.not_available")
    const text = [
      `📍 ${t("map_info.location_data")}`,
      `${t("map_info.points")}: ${p.point_count || 0}`,
      p.h3_index ? `${t("map_info.h3_index")}: ${p.h3_index}` : "",
      `${t("map_info.time_range")}: ${format(p.earliest_point)} → ${format(p.latest_point)}`,
    ]
    let center = p.center
    try {
      if (typeof center === "string") center = JSON.parse(center)
    } catch {
      center = null
    }
    if (Array.isArray(center))
      text.push(
        `${t("map_info.center")}: ${Number(center[0]).toFixed(6)}, ${Number(center[1]).toFixed(6)}`,
      )
    popup = new library.Popup({ maxWidth: "320px" })
      .setLngLat(event.lngLat)
      .setText(text.filter(Boolean).join("\n"))
      .addTo(map)
  }
  function clear() {
    close()
    clearHover()
    for (const id of ["hexagons-fill", "hexagons-line"])
      if (map.getLayer(id)) map.removeLayer(id)
    if (map.getSource("hexagons")) map.removeSource("hexagons")
  }
  map.on("click", "hexagons-fill", click)
  map.on("mousemove", "hexagons-fill", hover)
  map.on("mouseleave", "hexagons-fill", clearHover)
  return {
    show(data) {
      if (disposed) return
      clear()
      map.addSource("hexagons", { type: "geojson", data, generateId: true })
      const opacity = [
        "case",
        ["boolean", ["feature-state", "hover"], false],
        0.8,
        0.3,
      ]
      map.addLayer({
        id: "hexagons-fill",
        type: "fill",
        source: "hexagons",
        paint: { "fill-color": "#3388ff", "fill-opacity": opacity },
      })
      map.addLayer({
        id: "hexagons-line",
        type: "line",
        source: "hexagons",
        paint: {
          "line-color": "#3388ff",
          "line-width": [
            "case",
            ["boolean", ["feature-state", "hover"], false],
            2,
            1,
          ],
          "line-opacity": [
            "case",
            ["boolean", ["feature-state", "hover"], false],
            1,
            0.3,
          ],
        },
      })
    },
    destroy() {
      if (disposed) return
      disposed = true
      map.off("click", "hexagons-fill", click)
      map.off("mousemove", "hexagons-fill", hover)
      map.off("mouseleave", "hexagons-fill", clearHover)
      clear()
    },
  }
}
