import { pointsFromDevice } from "../algorithms/device_windows.js"
import { arcifyFlights } from "../algorithms/flight_arcs.js"
import { flightWindows, maskLines } from "../algorithms/flight_mask.js"
import { RouteSegmenter } from "../algorithms/route_segmenter.js"

export async function readRouteSnapshot(
  reader,
  state,
  { purpose, signal, deviceWindows = [], routeOptions = {} } = {},
) {
  const params = {
    start_at: state.range.startAt,
    end_at: state.range.endAt,
    import_id: state.range.importId,
  }
  const all = await reader.pages("points", params, { signal })
  const points = pointsFromDevice(all, deviceWindows)
  const routes = RouteSegmenter.pointsToRoutes(points, routeOptions)
  if (purpose === "replay") {
    const photos = state.photosEnabled
      ? await reader.pages(
          "photos",
          { start_date: state.range.startAt, end_date: state.range.endAt },
          { signal },
        )
      : []
    return { points, photos, geojson: routes }
  }
  if (purpose !== "poster" || !state.flightsEnabled)
    return { points, geojson: routes }
  const { data: flights } = await reader.read("flights", params, { signal })
  const arcs = arcifyFlights(flights)
  return {
    points,
    flights: arcs,
    geojson: {
      ...routes,
      features: [
        ...maskLines(routes, flightWindows(flights)).features,
        ...arcs.features,
      ],
    },
  }
}
