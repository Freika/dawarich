import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { pointMatchesActiveDateRange } from "maps_maplibre/utils/realtime_date_filter"

export function handleNewPoint(controller, pointData) {
  const mapsController = controller.mapsV2Controller
  if (!mapsController) {
    console.warn("[Realtime Controller] Maps controller not found")
    return
  }

  const [lat, lon, battery, altitude, timestamp, velocity, id, countryName] =
    pointData

  if (
    !pointMatchesActiveDateRange(timestamp, mapsController.realtimeDateRange())
  ) {
    return
  }

  mapsController.mapDataManager?.invalidatePoints({ appendOnly: true })
  controller.scheduleLiveRefresh()

  controller.updateRecentPoint(parseFloat(lon), parseFloat(lat), {
    id: parseInt(id, 10),
    battery: parseFloat(battery) || null,
    altitude: parseFloat(altitude) || null,
    timestamp: timestamp,
    velocity: parseFloat(velocity) || null,
    country_name: countryName || null,
  })

  controller.zoomToPoint(parseFloat(lon), parseFloat(lat))

  Toast.info(translate("messages.new_location_recorded"))
}

export function refreshLiveLayers(controller) {
  const mapsController = controller.mapsV2Controller
  if (!mapsController) return

  mapsController.layerManager?.getLayer("points-mvt")?.refresh()
  mapsController.layerManager?.getLayer("map-editor")?.reapplyTileFilters()
  mapsController.layerManager
    ?.getLayer("scratch")
    ?.update()
    .catch((error) => {
      console.warn(
        "[Realtime Controller] Failed to refresh visited countries:",
        error,
      )
      Toast.retry(
        translate("messages.failed_to_load_visited_countries"),
        translate("messages.retry"),
        () => mapsController.layerManager?.getLayer("scratch")?.update(),
      )
    })
}

export function updateRecentPoint(
  controller,
  longitude,
  latitude,
  properties = {},
) {
  const mapsController = controller.mapsV2Controller
  if (!mapsController) {
    console.warn("[Realtime Controller] Maps controller not found")
    return
  }

  const recentPointLayer = mapsController.layerManager?.getLayer("recentPoint")
  if (!recentPointLayer) {
    console.warn("[Realtime Controller] Recent point layer not found")
    return
  }

  if (controller.liveModeEnabled) {
    recentPointLayer.show()
    recentPointLayer.updateRecentPoint(longitude, latitude, properties)
  }
}

export function zoomToPoint(controller, longitude, latitude) {
  const mapsController = controller.mapsV2Controller
  if (!mapsController || !mapsController.map) {
    console.warn("[Realtime Controller] Map not available for zooming")
    return
  }

  const map = mapsController.map

  map.flyTo({
    center: [longitude, latitude],
    zoom: Math.max(map.getZoom(), 14),
    duration: 2000,
    essential: true,
  })
}
