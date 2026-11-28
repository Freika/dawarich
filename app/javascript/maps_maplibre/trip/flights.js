import Flash from "controllers/flash_controller"
import { translate } from "i18n"
import { FlightsLayer } from "maps_maplibre/layers/flights_layer"
import { ApiClient } from "maps_maplibre/services/api_client"
import { setButtonActive } from "maps_maplibre/trip/button_state"
import { flightWindows } from "maps_maplibre/utils/flight_mask"

export async function toggleTripFlights(controller) {
  controller.flightsActive = !controller.flightsActive

  if (!controller.flightsActive) {
    controller.flightsLayer?.hide()
    applyFlightMask(controller)
    setButtonActive(controller.flightsToggleBtnTarget, false)
    return
  }

  if (!controller.flightsGeoJSON) {
    const apiClient = new ApiClient(controller.apiKeyValue)
    try {
      controller.flightsGeoJSON = await apiClient.fetchFlights({
        start_at: controller.startedAtValue,
        end_at: controller.endedAtValue,
      })
    } catch (e) {
      console.error("[TripMapLibre] Error fetching flights:", e)
      // Drop the cache so the next click retries the fetch.
      controller.flightsGeoJSON = null
      controller.flightsActive = false
      setButtonActive(controller.flightsToggleBtnTarget, false)
      Flash.show(
        "error",
        translate("messages.could_not_load_flights_please_try_again"),
      )
      return
    }
  }

  if (!controller.flightsGeoJSON.features?.length) {
    // Drop the cache so flights added to AirTrail later in the session are
    // picked up on the next click instead of staying empty.
    controller.flightsGeoJSON = null
    controller.flightsActive = false
    setButtonActive(controller.flightsToggleBtnTarget, false)
    Flash.show("notice", translate("messages.no_flights_found_for_this_trip"))
    return
  }

  if (!controller.flightsLayer) {
    controller.flightsLayer = new FlightsLayer(controller.map, {
      style: controller.mapStyleValue,
    })
    controller.flightsLayer.add(controller.flightsGeoJSON)
  } else {
    controller.flightsLayer.update(controller.flightsGeoJSON)
    controller.flightsLayer.show()
  }

  applyFlightMask(controller)
  setButtonActive(controller.flightsToggleBtnTarget, true)
}

export function applyFlightMask(controller) {
  const tripStart = Date.parse(controller.startedAtValue) / 1000
  const tripEnd = Date.parse(controller.endedAtValue) / 1000
  const windows =
    controller.flightsActive && controller.flightsLayer?.visible
      ? flightWindows(controller.flightsGeoJSON).filter(
          ([from, to]) => to >= tripStart && from <= tripEnd,
        )
      : []
  controller.dayRoutesLayer?.setExcludedWindows(windows)
}
