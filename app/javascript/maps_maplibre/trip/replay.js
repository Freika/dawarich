import Flash from "controllers/flash_controller"
import { translate } from "i18n"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import {
  setTripReplayPhotosActive,
  tripReplayPhotos,
} from "maps_maplibre/trip/photos"
import { ensureTripPoints } from "maps_maplibre/trip/points"

export async function toggleTripReplay(controller) {
  if (!controller.hasReplayPanelTarget || controller.replayToggling) return
  controller.replayPanel ||= new ReplayPanel({
    controller,
    map: controller.map,
    dayRoutesLayer: controller.dayRoutesLayer,
    element: controller.element,
    timezone: controller.timezoneValue,
    loadPoints: async () => {
      const points = await ensureTripPoints(controller)
      return controller.element.isConnected ? points : []
    },
    getPhotos: () => tripReplayPhotos(controller),
    onReplayPhotosActive: (active) =>
      setTripReplayPhotosActive(controller, active),
  })
  controller.replayToggling = true
  try {
    await controller.replayPanel.toggle()
  } catch (error) {
    console.error("[TripMapLibre] Error fetching points:", error)
    Flash.show(
      "error",
      translate("messages.failed_to_load_location_data_please_try_again"),
    )
  } finally {
    controller.replayToggling = false
  }
}
