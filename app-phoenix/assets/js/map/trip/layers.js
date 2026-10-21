import { flightWindows } from "../algorithms/flight_mask.js"
import { FlightsLayer } from "../layers/flights.js"
import { DayRoutesLayer } from "./days.js"
import { TripPlanLayer } from "./plan.js"
export function groupDays(points, timezone) {
  const format = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
  const days = {}
  for (const point of points) {
    const raw = point.properties?.timestamp ?? point.timestamp
    const date = new Date(
      typeof raw === "number" && raw < 10000000000 ? raw * 1000 : raw,
    )
    if (!Number.isFinite(date.getTime())) continue
    const parts = Object.fromEntries(
      format.formatToParts(date).map((p) => [p.type, p.value]),
    )
    const day = `${parts.year}-${parts.month}-${parts.day}`
    days[day] ??= []
    days[day].push(point)
  }
  for (const rows of Object.values(days))
    rows.sort(
      (a, b) =>
        new Date(
          typeof a.timestamp === "number" && a.timestamp < 10000000000
            ? a.timestamp * 1000
            : a.timestamp,
        ).getTime() -
        new Date(
          typeof b.timestamp === "number" && b.timestamp < 10000000000
            ? b.timestamp * 1000
            : b.timestamp,
        ).getTime(),
    )
  return days
}
export function createTripLayers({
  map,
  library,
  labels = {},
  onDay = () => {},
}) {
  let current = null,
    selected = null,
    destroyed = false,
    flights = null,
    overviewFitted = false,
    routesFitted = false
  const days = new DayRoutesLayer(map, { library, labels }),
    plan = new TripPlanLayer(map, { library, numbered: true })
  function clear() {
    days.remove()
    plan.remove()
    flights?.remove()
    flights = null
    if (map.getLayer("trip-overview")) map.removeLayer("trip-overview")
    if (map.getSource("trip-overview")) map.removeSource("trip-overview")
  }
  function render() {
    if (destroyed || !current) return
    clear()
    const { data, snapshot, config } = current
    if (snapshot.points?.length) {
      days.addDayRoutes(
        groupDays(snapshot.points, data.config.range.timezone),
        data.config.routeOptions,
      )
      if (!routesFitted && days.getFullBounds()) {
        map.fitBounds(days.getFullBounds(), { padding: 50, maxZoom: 15 })
        routesFitted = true
      }
      days.setupInteractions({
        onDayClick(day) {
          selected = day
          days.selectDay(day)
          onDay({ day })
        },
      })
      if (selected) days.selectDay(selected)
      if (config.flightsEnabled && snapshot.flights) {
        flights = new FlightsLayer(map, { library })
        flights.add(snapshot.flights)
        days.maskRoutes(flightWindows(snapshot.flights))
      }
    } else if (data.path?.length >= 2) {
      map.addSource("trip-overview", {
        type: "geojson",
        data: {
          type: "Feature",
          properties: {},
          geometry: { type: "LineString", coordinates: data.path },
        },
      })
      map.addLayer({
        id: "trip-overview",
        type: "line",
        source: "trip-overview",
        paint: {
          "line-color": "#6366F1",
          "line-width": 3,
          "line-opacity": 0.8,
        },
      })
      if (!overviewFitted && !routesFitted) {
        const bounds = new library.LngLatBounds()
        for (const coordinate of data.path) bounds.extend(coordinate)
        if (!bounds.isEmpty()) map.fitBounds(bounds, { padding: 50, maxZoom: 15 })
        overviewFitted = true
      }
    }
    if (config.planEnabled && data.plan) plan.add(data.plan)
  }
  map.on("style.load", render)
  return {
    update(data, snapshot, config) {
      current = { data, snapshot, config }
      render()
    },
    selectDay(day) {
      selected = day
      day ? days.selectDay(day) : days.selectAllDays()
      const bounds = day ? days.getDayBounds(day) : days.getFullBounds()
      if (bounds) map.fitBounds(bounds, { padding: 50, maxZoom: 15 })
    },
    focusPlan(longitude, latitude) {
      plan.focus(longitude, latitude)
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      map.off("style.load", render)
      clear()
      current = null
    },
    get days() {
      return days
    },
  }
}
