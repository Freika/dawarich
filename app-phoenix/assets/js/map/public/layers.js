import { RecentPointLayer } from "../layers/recent_point.js"
import { DayRoutesLayer } from "../trip/days.js"
import { groupDays } from "../trip/layers.js"
export function createPublicLayers({ map, library, onDay = () => {} }) {
  const days = new DayRoutesLayer(map, { library }),
    recent = new RecentPointLayer(map)
  let current = null,
    selected = null
  function clear() {
    current = null
    days.remove()
    recent.remove()
    if (map.getLayer("public-route")) map.removeLayer("public-route")
    if (map.getSource("public-route")) map.removeSource("public-route")
  }
  function render() {
    if (!current) return
    const { data, config } = current
    days.remove()
    recent.remove()
    if (map.getLayer("public-route")) map.removeLayer("public-route")
    if (map.getSource("public-route")) map.removeSource("public-route")
    let coords
    if (config.byDay) {
      days.addDayRoutes(
        groupDays(
          data.points.map(([longitude, latitude, timestamp]) => ({
            longitude,
            latitude,
            timestamp,
          })),
          config.range.timezone,
        ),
        config.routeOptions,
      )
      days.setupInteractions({
        onDayClick(day) {
          selected = day
          days.selectDay(day)
          onDay(day)
        },
      })
      if (selected) days.selectDay(selected)
      coords = data.points.map(([lon, lat]) => [lon, lat])
    } else {
      coords = (config.publicType === "live" ? data.route : data.points).map(
        ([lon, lat]) => [lon, lat],
      )
      if (coords.length) {
        map.addSource("public-route", {
          type: "geojson",
          data: {
            type: "Feature",
            properties: {},
            geometry: { type: "LineString", coordinates: coords },
          },
        })
        map.addLayer({
          id: "public-route",
          type: "line",
          source: "public-route",
          paint: {
            "line-color": "#6366F1",
            "line-width": 3,
            "line-opacity": 0.8,
          },
        })
      }
    }
    if (config.publicType === "live" && data.points.length) {
      const [lon, lat, timestamp] = data.points[0]
      recent.add()
      recent.updateRecentPoint(lon, lat, { timestamp })
      if (!coords.length) coords = [[lon, lat]]
    }
    if (coords.length) {
      const bounds = new library.LngLatBounds()
      for (const point of coords) bounds.extend(point)
      map.fitBounds(bounds, { padding: 40, maxZoom: 15, duration: 0 })
    }
  }
  map.on("style.load", render)
  return {
    show(data, config) {
      current = { data, config }
      render()
    },
    clear,
    selectDay(day) {
      selected = day
      day ? days.selectDay(day) : days.selectAllDays()
      const bounds = day ? days.getDayBounds(day) : days.getFullBounds()
      if (bounds) map.fitBounds(bounds, { padding: 40, maxZoom: 15 })
    },
    destroy() {
      clear()
      map.off("style.load", render)
    },
  }
}
