import Flash from "controllers/flash_controller"
import { translate } from "i18n"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
import { ApiClient } from "maps_maplibre/services/api_client"
import { buildDayRouteCollections } from "maps_maplibre/utils/day_route_collections"
import { pointsFromDevice } from "maps_maplibre/utils/device_points"
import { flightWindows, maskLines } from "maps_maplibre/utils/flight_mask"
import { buildTripGeojson, TripProvider } from "poster_studio/data/providers"

export function ensureTripPoints(controller) {
  controller.pointsPromise ||= loadTripPoints(controller).catch((error) => {
    controller.pointsPromise = null
    throw error
  })
  return controller.pointsPromise
}

async function loadTripPoints(controller) {
  setPointsLoading(controller, true)
  try {
    const { points } = await new ApiClient(
      controller.apiKeyValue,
    ).fetchAllPoints({
      start_at: controller.startedAtValue,
      end_at: controller.endedAtValue,
    })
    const allPoints = pointsFromDevice(
      points || [],
      controller.deviceWindowsValue,
    )
    const grouper = new ReplayManager({ timezone: controller.timezoneValue })
    grouper.setPoints(allPoints)
    const pointsByDay = {}
    for (const dayKey of grouper.availableDays) {
      pointsByDay[dayKey] = grouper.getPointsForDay(dayKey)
    }

    controller.allPoints = allPoints
    controller.dayRouteCollections = buildDayRouteCollections(pointsByDay, {
      distanceThresholdMeters: controller.metersBetweenRoutesValue,
      timeThresholdMinutes: controller.minutesBetweenRoutesValue,
    })
    return allPoints
  } finally {
    setPointsLoading(controller, false)
  }
}

function setPointsLoading(controller, loading) {
  controller.showLoading(loading)
  if (loading) {
    controller.busyButtons = ["posterBtn", "videoBtn", "replayToggleBtn"]
      .filter(
        (name) =>
          controller[`has${name[0].toUpperCase()}${name.slice(1)}Target`],
      )
      .map((name) => controller[`${name}Target`])
      .filter((button) => !button.disabled)
  }
  for (const button of controller.busyButtons || []) {
    button.disabled = loading
    if (loading) button.setAttribute("aria-busy", "true")
    else button.removeAttribute("aria-busy")
  }
}

export async function openTripStudio(controller, eventName) {
  try {
    await ensureTripPoints(controller)
  } catch (error) {
    console.error("[TripMapLibre] Error fetching points:", error)
    Flash.show(
      "error",
      translate("messages.failed_to_load_location_data_please_try_again"),
    )
    return
  }
  if (!controller.element.isConnected) return

  document.dispatchEvent(
    new CustomEvent(eventName, {
      detail: { provider: tripPosterProvider(controller) },
    }),
  )
}

export function tripPosterProvider(controller) {
  const geojson = buildTripGeojson({
    dayRouteCollections: controller.dayRouteCollections,
  })
  // Keep the GPS snapshot for video, including switches between studios.
  const posterGeojson =
    controller.flightsActive && controller.flightsLayer?.visible
      ? {
          type: "FeatureCollection",
          features: [
            ...maskLines(geojson, flightWindows(controller.flightsGeoJSON))
              .features,
            ...(controller.flightsLayer.data?.features ?? []),
          ],
        }
      : geojson
  return new TripProvider({
    geojson,
    posterGeojson,
    startAt: controller.startedAtValue,
    endAt: controller.endedAtValue,
    title: controller.tripNameValue,
    points: controller.allPoints,
    timezone: controller.timezoneValue,
  })
}
